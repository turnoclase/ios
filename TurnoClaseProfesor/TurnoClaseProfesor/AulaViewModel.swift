// Copyright 2015 Ion Jaureguialzo Sarasola.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// AulaViewModel.swift
// TurnoClaseProfesor

import AudioToolbox
import Combine
import Foundation
import SwiftUI

import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

import Localize_Swift

import TurnoClaseShared

// MARK: - Timeout

private func withTimeout<T: Sendable>(segundos: Double, operacion: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operacion() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(segundos * 1000000000))
            throw URLError(.timedOut)
        }
        let resultado = try await group.next()!
        group.cancelAll()
        return resultado
    }
}

@MainActor
class AulaViewModel: ObservableObject {
    // MARK: - Estado publicado

    @Published var codigoAula: String = "..."
    @Published var enCola: Int = 0
    @Published var nombreAlumno: String = ""
    @Published var numAulas: Int = 0 {
        didSet {
            actualizarPageControl()
        }
    }

    @Published var aulaActual: Int = 0
    @Published var mostrarIndicador: Bool = false
    @Published var invitado: Bool = false
    @Published var PIN: String = "..."
    @Published var etiquetaAula: String = ""
    @Published var tiempoEspera: Int = 5

    @Published var cargando: Bool = true
    @Published var errorRed: Bool = false

    /// Duración mínima (en segundos) que se muestra la animación de carga.
    var duracionMinimaCarga: Double = 1.0

    // MARK: - Propiedades internas

    // Alertas / diálogos
    @Published var alertaActiva: AlertaAula? = nil

    let MAX_AULAS = 16
    var uid: String?
    var refAula: DocumentReference?
    var refMisAulas: CollectionReference?
    var listenerAula: ListenerRegistration?
    var listenerCola: ListenerRegistration?
    var recuentoAnterior: Int = 0
    lazy var functions = Functions.functions(region: "europe-west1")
    let tiempos = [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60]

    // Para evitar actualizaciones del listener mientras se avanza la cola
    var avanzandoCola: Bool = false

    // Para test UI
    var n = 2
    private var inicioCarga: Date = .distantPast

    // MARK: - Duración mínima de carga

    /// Inicia la carga y registra el instante de inicio.
    func iniciarCarga() {
        inicioCarga = Date()
        cargando = true
    }

    /// Termina la carga respetando la duración mínima configurada en `duracionMinimaCarga`.
    func terminarCarga() {
        let transcurrido = Date().timeIntervalSince(inicioCarga)
        let restante = duracionMinimaCarga - transcurrido
        if restante > 0 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(restante * 1000000000))
                self.cargando = false
            }
        } else {
            cargando = false
        }
    }

    // MARK: - Inicialización

    func iniciar() {
        // Detectar el estado de la conexión de red
        reachability.whenReachable = { [weak self] reachability in
            guard let self = self else { return }
            if reachability.connection == .wifi {
                log.info("Red Wifi")
            } else {
                log.info("Red móvil")
            }
            Task { @MainActor in
                guard self.uid != nil, self.errorRed else { return }
                self.errorRed = false
                self.desconectarListeners()
                self.conectarAula()
            }
        }

        reachability.whenUnreachable = { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.terminarCarga()
                self.errorRed = true
                self.actualizarAulaUI(codigo: "?", enCola: 0)
                self.nombreAlumno = ""
                self.invitado = false
                self.aulaActual = 0
                self.mostrarIndicador = false
                self.desconectarListeners()
                log.emergency("Red no disponible")
            }
        }

        do {
            try reachability.startNotifier()
        } catch {
            log.error("No se ha podido iniciar el notificador de estado de red")
        }

        log.info("Iniciando la aplicación...")

        if UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT") {
            actualizarAulaUI(codigo: "BE131", enCola: 0)
            nombreAlumno = ""
            PIN = "1234"
            numAulas = 2
        } else {
            actualizarAulaUI(codigo: "...", enCola: 0)
            nombreAlumno = ""
            iniciarCarga()
            errorRed = false
            mostrarIndicador = false
            numAulas = 0

            Auth.auth().signInAnonymously { [weak self] result, error in
                guard let self = self else { return }
                if let resultado = result {
                    Task { @MainActor in
                        self.uid = resultado.user.uid
                        log.info("Registrado como usuario con UID: \(self.uid ??? "[Desconocido]")")

                        let uidAnterior = UserDefaults.standard.string(forKey: "uidAnterior") ?? ""
                        if !uidAnterior.isEmpty && uidAnterior != self.uid {
                            self.uid = uidAnterior
                            log.info("Ya estaba registrado con UID: \(uidAnterior)")
                        } else {
                            UserDefaults.standard.set(self.uid, forKey: "uidAnterior")
                        }

                        let codigoAulaConectada = UserDefaults.standard.string(forKey: "codigoAulaConectada") ?? ""
                        let pinConectada = UserDefaults.standard.string(forKey: "pinConectada") ?? ""

                        if !codigoAulaConectada.isEmpty && !pinConectada.isEmpty {
                            self.buscarAula(codigo: codigoAulaConectada, pin: pinConectada)
                        } else {
                            self.conectarAula()
                        }
                    }
                } else {
                    Task { @MainActor in
                        log.error("Error de inicio de sesión: \(error!.localizedDescription)")
                        self.terminarCarga()
                        self.errorRed = true
                        self.actualizarAulaUI(codigo: "?", enCola: 0)
                    }
                }
            }
        }
    }

    // MARK: - Conectar aula

    func conectarAula(posicion: Int = 0) {
        guard let uid = uid else { return }
        iniciarCarga()
        refMisAulas = db.collection("profesores").document(uid).collection("aulas")
        Task {
            do {
                let querySnapshot = try await withTimeout(segundos: 10) {
                    try await self.refMisAulas?.order(by: "timestamp").getDocuments(source: .server)
                }
                let total = querySnapshot?.documents.count ?? 0
                numAulas = total
                if posicion >= 0 && posicion < total {
                    if let seleccionada = querySnapshot?.documents[posicion] {
                        log.info("Conectado a aula existente")
                        refAula = seleccionada.reference
                        conectarListener()
                    }
                } else {
                    log.info("Creando nueva aula...")
                    crearAula()
                }
            } catch {
                log.error("Error al recuperar la lista de aulas \(error.localizedDescription)")
                terminarCarga()
                errorRed = true
                actualizarAulaUI(codigo: "?", enCola: 0)
            }
        }
    }

    // MARK: - Crear / añadir aula

    func crearAula() {
        mostrarIndicador = true
        Task {
            do {
                let ref = try await crearNuevaAula()
                refAula = ref
                conectarListener()
            } catch {
                log.error("Error al crear el aula: \(error.localizedDescription)")
                terminarCarga()
                errorRed = true
                actualizarAulaUI(codigo: "?", enCola: 0)
            }
        }
    }

    func anyadirAula() {
        mostrarIndicador = true
        Task {
            do {
                _ = try await crearNuevaAula()
            } catch {
                log.error("Error al crear el aula: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    private func crearNuevaAula() async throws -> DocumentReference? {
        let result = try await functions.httpsCallable("nuevoCodigo").call(["keepalive": false])
        guard let codigo = (result.data as? [String: Any])?["codigo"] as? String else { return nil }
        log.info("Nuevo código de aula: \(codigo)")

        let datos: [String: Any] = [
            "codigo": codigo,
            "timestamp": FieldValue.serverTimestamp(),
            "pin": String(format: "%04d", Int.random(in: 0 ... 9999)),
            "espera": 5,
        ]

        let ref = try await refMisAulas?.addDocument(data: datos)
        log.info("Aula creada")

        numAulas += 1

        return ref
    }

    // MARK: - Listeners

    func conectarListener() {
        guard listenerAula == nil, let refAula = refAula else { return }
        listenerAula = refAula.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error {
                    log.error("Error en listener de aula: \(error.localizedDescription)")
                    self.terminarCarga()
                    self.errorRed = true
                    self.actualizarAulaUI(codigo: "?", enCola: 0)
                    return
                }
                if documentSnapshot?.exists == true {
                    if let aula = documentSnapshot?.data() {
                        log.info("Actualizando datos del aula...")
                        self.terminarCarga()
                        self.errorRed = false
                        self.actualizarAulaUI(codigo: aula["codigo"] ??? "?")
                        self.PIN = aula["pin"] ??? "?"
                        self.tiempoEspera = aula["espera"] as? Int ?? 5
                        self.etiquetaAula = aula["etiqueta"] ??? ""

                        if self.listenerCola == nil {
                            self.listenerCola = self.refAula?.collection("cola").addSnapshotListener { [weak self] querySnapshot, error in
                                guard let self = self else { return }
                                Task { @MainActor in
                                    if let error = error {
                                        log.error("Error al recuperar datos: \(error.localizedDescription)")
                                        self.terminarCarga()
                                        self.errorRed = true
                                    } else if let snapshot = querySnapshot {
                                        self.errorRed = false
                                        let docs = snapshot.documents
                                            .sorted { ($0.data()["timestamp"] as? Timestamp)?.seconds ?? 0
                                                < ($1.data()["timestamp"] as? Timestamp)?.seconds ?? 0
                                            }
                                        self.actualizarContador(docs.count)
                                        if !self.avanzandoCola {
                                            await self.mostrarSiguienteDesdeSnapshot(docs: docs)
                                            self.feedbackTactilNotificacion()
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    log.info("El aula ha desaparecido")
                    if !self.invitado {
                        self.actualizarAulaUI(codigo: "?", enCola: 0)
                        self.PIN = "?"
                        self.desconectarListeners()
                        self.iniciarCarga()
                        self.conectarAula()
                    } else {
                        self.desconectarAula()
                    }
                }
            }
        }
    }

    func desconectarListeners() {
        listenerAula?.remove()
        listenerAula = nil
        listenerCola?.remove()
        listenerCola = nil
    }

    // Muestra el nombre del primer alumno a partir del snapshot del listener de cola.
    // No requiere consultas adicionales al servidor para el caso pasivo.
    private func mostrarSiguienteDesdeSnapshot(docs: [QueryDocumentSnapshot]) async {
        guard let primerDoc = docs.first,
              let alumnoId = primerDoc.data()["alumno"] as? String
        else {
            nombreAlumno = ""
            return
        }
        do {
            // Usar .default: resuelve con caché local si está disponible,
            // o del servidor si no. Nunca bloquea indefinidamente.
            let alumnoDoc = try await db.collection("alumnos").document(alumnoId).getDocument()
            if alumnoDoc.exists, let alumno = alumnoDoc.data() {
                nombreAlumno = alumno["nombre"] as? String ?? "?"
            } else {
                nombreAlumno = "?"
            }
        } catch {
            log.error("Error al obtener nombre de alumno: \(error.localizedDescription)")
            nombreAlumno = "?"
        }
    }

    // MARK: - Mostrar siguiente

    func mostrarSiguiente(avanzarCola: Bool = false) {
        log.info("Mostrando el siguiente alumno...")
        guard let refAula = refAula else { return }
        if avanzarCola { avanzandoCola = true }
        Task {
            do {
                let querySnapshot = try await refAula.collection("cola").order(by: "timestamp").getDocuments(source: .server)
                let docs = querySnapshot.documents
                guard docs.count > 0 else {
                    log.info("Cola vacía")
                    nombreAlumno = codigoAula != "?" ? "" : "No hay conexión de red".localized()
                    avanzandoCola = false
                    return
                }
                let refPosicion = docs[0].reference
                let posicionDoc = try await refPosicion.getDocument(source: .server)
                guard let posicion = posicionDoc.data(),
                      let alumnoId = posicion["alumno"] as? String
                else {
                    avanzandoCola = false
                    return
                }
                let alumnoDoc = try await db.collection("alumnos").document(alumnoId).getDocument(source: .server)
                if alumnoDoc.exists, let alumno = alumnoDoc.data() {
                    if avanzarCola {
                        // Mover el alumno actual a espera y borrarlo de la cola
                        try await refAula.collection("espera").document(alumnoId).setData([
                            "timestamp": FieldValue.serverTimestamp(),
                        ])
                        try await refPosicion.delete()
                        avanzandoCola = false
                        // Mostrar el siguiente alumno en cola (si lo hay)
                        await mostrarSiguienteDesdeFirestore(refAula: refAula, docs: docs)
                    } else {
                        nombreAlumno = alumno["nombre"] as? String ?? "?"
                    }
                } else {
                    log.error("El alumno no existe")
                    nombreAlumno = "?"
                    avanzandoCola = false
                }
            } catch {
                log.error("Error al recuperar datos: \(error.localizedDescription)")
                avanzandoCola = false
            }
        }
    }

    // Muestra el siguiente alumno en la cola (el que queda tras avanzar)
    private func mostrarSiguienteDesdeFirestore(refAula: DocumentReference, docs: [QueryDocumentSnapshot]) async {
        // Si había más de un alumno, el siguiente es docs[1]
        guard docs.count > 1 else {
            log.info("No hay más alumnos en cola")
            nombreAlumno = ""
            return
        }
        do {
            let refSiguiente = docs[1].reference
            let siguienteDoc = try await refSiguiente.getDocument(source: .server)
            guard let posicion = siguienteDoc.data(),
                  let alumnoId = posicion["alumno"] as? String
            else {
                nombreAlumno = ""
                return
            }
            let alumnoDoc = try await db.collection("alumnos").document(alumnoId).getDocument(source: .server)
            if alumnoDoc.exists, let alumno = alumnoDoc.data() {
                nombreAlumno = alumno["nombre"] as? String ?? "?"
            } else {
                nombreAlumno = ""
            }
        } catch {
            log.error("Error al recuperar el siguiente alumno: \(error.localizedDescription)")
            nombreAlumno = ""
        }
    }

    // MARK: - Buscar aula (invitado)

    func buscarAula(codigo: String?, pin: String?) {
        guard let codigo = codigo, let pin = pin else { return }
        log.debug("Buscando UID del aula: \(codigo):\(pin)")
        iniciarCarga()
        errorRed = false
        Task {
            do {
                let querySnapshot = try await withTimeout(segundos: 10) {
                    try await db.collectionGroup("aulas")
                        .whereField("codigo", isEqualTo: codigo.uppercased())
                        .whereField("pin", isEqualTo: pin)
                        .getDocuments(source: .server)
                }
                if querySnapshot.documents.count > 0 {
                    log.info("Aula encontrada: \(codigo)")
                    UserDefaults.standard.set(codigo, forKey: "codigoAulaConectada")
                    UserDefaults.standard.set(pin, forKey: "pinConectada")
                    desconectarListeners()
                    invitado = true
                    refAula = querySnapshot.documents.first?.reference
                    conectarListener()
                } else {
                    log.error("Aula no encontrada")
                    terminarCarga()
                    if UserDefaults.standard.string(forKey: "codigoAulaConectada") == nil {
                        alertaActiva = .errorConexion
                    }
                    desconectarAula()
                }
            } catch {
                log.error("Error al recuperar datos: \(error.localizedDescription)")
                terminarCarga()
                errorRed = true
                actualizarAulaUI(codigo: "?", enCola: 0)
            }
        }
    }

    func desconectarAula() {
        UserDefaults.standard.removeObject(forKey: "codigoAulaConectada")
        UserDefaults.standard.removeObject(forKey: "pinConectada")
        invitado = false
        desconectarListeners()
        conectarAula(posicion: aulaActual)
    }

    // MARK: - Reintentar conexión

    func reintentar() {
        errorRed = false
        desconectarListeners()
        let codigoAulaConectada = UserDefaults.standard.string(forKey: "codigoAulaConectada") ?? ""
        let pinConectada = UserDefaults.standard.string(forKey: "pinConectada") ?? ""
        if !codigoAulaConectada.isEmpty, !pinConectada.isEmpty {
            buscarAula(codigo: codigoAulaConectada, pin: pinConectada)
        } else {
            conectarAula(posicion: aulaActual)
        }
    }

    // MARK: - Borrar aula

    func borrarAulaReconectar(codigo: String) {
        mostrarIndicador = true
        desconectarListeners()
        Task {
            do {
                let querySnapshot = try await refMisAulas?
                    .whereField("codigo", isEqualTo: codigo.uppercased())
                    .getDocuments(source: .server)
                guard let ref = querySnapshot?.documents.first?.reference else { return }
                try await ref.delete()
                log.info("Aula borrada")
                numAulas -= 1
                if aulaActual == numAulas {
                    aulaActual = max(0, aulaActual - 1)
                }
                conectarAula(posicion: aulaActual)
            } catch {
                log.error("Error al borrar el aula: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Actualizar etiqueta

    func actualizarEtiqueta(_ nuevaEtiqueta: String) {
        etiquetaAula = nuevaEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await refAula?.updateData(["etiqueta": etiquetaAula])
                log.info("Aula actualizada")
            } catch {
                log.error("Error al actualizar el aula: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Actualizar tiempo de espera

    func actualizarTiempoEspera(_ tiempo: Int) {
        tiempoEspera = tiempo
        log.info("Establecer tiempo de espera en \(tiempo) minutos...")
        Task {
            do {
                try await refAula?.updateData(["espera": tiempo])
                log.info("Aula actualizada")
            } catch {
                log.error("Error al actualizar el aula: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Navegación entre aulas

    func aulaAnterior() {
        if !invitado, numAulas > 1, aulaActual > 0 {
            aulaActual -= 1
            log.debug("Aula anterior")
            desconectarListeners()
            conectarAula(posicion: aulaActual)
        }
    }

    func aulaSiguiente() {
        if !invitado, numAulas > 1, aulaActual < numAulas - 1 {
            aulaActual += 1
            log.debug("Aula siguiente")
            desconectarListeners()
            conectarAula(posicion: aulaActual)
        }
    }

    // MARK: - Helpers privados

    private func actualizarAulaUI(codigo: String) {
        codigoAula = codigo
        log.info("Código de aula: \(codigo)")
    }

    private func actualizarAulaUI(codigo: String, enCola: Int) {
        actualizarAulaUI(codigo: codigo)
        actualizarContador(enCola)
    }

    private func actualizarContador(_ recuento: Int) {
        let sonidoActivado = UserDefaults.standard.bool(forKey: "QUEUE_NOT_EMPTY_SOUND")
        if sonidoActivado, recuentoAnterior == 0, recuento == 1 {
            #if targetEnvironment(macCatalyst)
            AudioServicesPlaySystemSound(SystemSoundID(0x00001000))
            #else
            AudioServicesPlaySystemSound(SystemSoundID(1315))
            #endif
        }
        recuentoAnterior = recuento
        enCola = recuento
        log.info("Alumnos en cola: \(recuento)")
    }

    private func actualizarPageControl() {
        mostrarIndicador = false
    }

    private func feedbackTactilNotificacion() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    func feedbackTactilLigero() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Capturas de pantalla (Fastlane)

    func simularBotonEnCola() {
        if UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT") {
            if n >= 0 {
                enCola = n
                nombreAlumno = Nombres.aleatorio()
            } else {
                enCola = 0
                nombreAlumno = ""
            }
            n -= 1
        }
    }
}

// MARK: - Tipo de alerta

enum AlertaAula: Identifiable {
    case errorConexion
    case confirmarBorrado(codigo: String)
    case conectarOtraAula
    case etiquetarAula
    case tiempoEspera
    case menuAcciones

    var id: String {
        switch self {
        case .errorConexion: return "errorConexion"
        case .confirmarBorrado: return "confirmarBorrado"
        case .conectarOtraAula: return "conectarOtraAula"
        case .etiquetarAula: return "etiquetarAula"
        case .tiempoEspera: return "tiempoEspera"
        case .menuAcciones: return "menuAcciones"
        }
    }
}
