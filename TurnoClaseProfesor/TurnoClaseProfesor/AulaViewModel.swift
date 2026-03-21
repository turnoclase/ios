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

import Foundation
import Combine
import SwiftUI
import AudioToolbox

import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

import Localize_Swift

import TurnoClaseShared

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

    // Alertas / diálogos
    @Published var alertaActiva: AlertaAula? = nil

    // MARK: - Propiedades internas

    let MAX_AULAS = 16
    var uid: String?
    var refAula: DocumentReference?
    var refMisAulas: CollectionReference?
    var listenerAula: ListenerRegistration?
    var listenerCola: ListenerRegistration?
    var recuentoAnterior: Int = 0
    lazy var functions = Functions.functions(region: "europe-west1")
    let tiempos = [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60]

    // Para test UI
    var n = 2

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
                if self.uid != nil {
                    self.conectarAula()
                }
            }
        }

        reachability.whenUnreachable = { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.actualizarAulaUI(codigo: "?", enCola: 0)
                self.nombreAlumno = "No hay conexión de red".localized()
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
            mostrarIndicador = false
            numAulas = 0

            Auth.auth().signInAnonymously() { [weak self] (result, error) in
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
                        self.actualizarAulaUI(codigo: "?", enCola: 0)
                    }
                }
            }
        }
    }

    // MARK: - Conectar aula

    func conectarAula(posicion: Int = 0) {
        guard let uid = uid else { return }
        refMisAulas = db.collection("profesores").document(uid).collection("aulas")
        refMisAulas?.order(by: "timestamp").getDocuments() { [weak self] (querySnapshot, error) in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error {
                    log.error("Error al recuperar la lista de aulas \(error.localizedDescription)")
                    self.actualizarAulaUI(codigo: "?", enCola: 0)
                } else {
                    let total = querySnapshot?.documents.count ?? 0
                    self.numAulas = total
                    if posicion >= 0 && posicion < total {
                        if let seleccionada = querySnapshot?.documents[posicion] {
                            log.info("Conectado a aula existente")
                            self.refAula = seleccionada.reference
                            self.conectarListener()
                        }
                    } else {
                        log.info("Creando nueva aula...")
                        self.crearAula()
                    }
                }
            }
        }
    }

    // MARK: - Crear / añadir aula

    func crearAula() {
        mostrarIndicador = true
        functions.httpsCallable("nuevoCodigo").call(["keepalive": false]) { [weak self] (result, error) in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error as NSError? {
                    if error.domain == FunctionsErrorDomain { log.error(error.localizedDescription) }
                }
                if let codigo = (result?.data as? [String: Any])?["codigo"] as? String {
                    log.info("Nuevo código de aula: \(codigo)")
                    self.refAula = self.refMisAulas?.addDocument(data: [
                        "codigo": codigo,
                        "timestamp": FieldValue.serverTimestamp(),
                        "pin": String(format: "%04d", Int.random(in: 0...9999)),
                        "espera": 5,
                    ]) { error in
                        Task { @MainActor in
                            if let error = error {
                                log.error("Error al crear el aula: \(error.localizedDescription)")
                            } else {
                                log.info("Aula creada")
                                self.numAulas += 1
                                self.conectarListener()
                            }
                        }
                    }
                }
            }
        }
    }

    func anyadirAula() {
        mostrarIndicador = true
        functions.httpsCallable("nuevoCodigo").call(["keepalive": false]) { [weak self] (result, error) in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error as NSError? {
                    if error.domain == FunctionsErrorDomain { log.error(error.localizedDescription) }
                }
                if let codigo = (result?.data as? [String: Any])?["codigo"] as? String {
                    log.info("Nuevo código de aula: \(codigo)")
                    self.refMisAulas?.addDocument(data: [
                        "codigo": codigo,
                        "timestamp": FieldValue.serverTimestamp(),
                        "pin": String(format: "%04d", Int.random(in: 0...9999)),
                        "espera": 5,
                    ]) { error in
                        Task { @MainActor in
                            if let error = error {
                                log.error("Error al crear el aula: \(error.localizedDescription)")
                            } else {
                                log.info("Aula creada")
                                self.numAulas += 1
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Listeners

    func conectarListener() {
        guard listenerAula == nil, let refAula = refAula else { return }
        listenerAula = refAula.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            Task { @MainActor in
                if documentSnapshot?.exists == true {
                    if let aula = documentSnapshot?.data() {
                        log.info("Actualizando datos del aula...")
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
                                    } else {
                                        let count = querySnapshot?.documents.count ?? 0
                                        self.actualizarContador(count)
                                        self.mostrarSiguiente()
                                        self.feedbackTactilNotificacion()
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

    // MARK: - Mostrar siguiente

    func mostrarSiguiente(avanzarCola: Bool = false) {
        log.info("Mostrando el siguiente alumno...")
        guard let refAula = refAula else { return }
        refAula.collection("cola").order(by: "timestamp").getDocuments() { [weak self] (querySnapshot, error) in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error {
                    log.error("Error al recuperar datos: \(error.localizedDescription)")
                    return
                }
                if let docs = querySnapshot?.documents, docs.count > 0 {
                    let refPosicion = docs[0].reference
                    refPosicion.getDocument { [weak self] (document, error) in
                        guard let self = self else { return }
                        Task { @MainActor in
                            if let posicion = document?.data() {
                                db.collection("alumnos").document(posicion["alumno"] as! String).getDocument { [weak self] (document, error) in
                                    guard let self = self else { return }
                                    Task { @MainActor in
                                        if let document = document, document.exists, let alumno = document.data() {
                                            self.nombreAlumno = alumno["nombre"] as? String ?? "?"
                                            if avanzarCola {
                                                self.refAula?.collection("espera").document(posicion["alumno"] as! String).setData([
                                                    "timestamp": FieldValue.serverTimestamp()
                                                ]) { error in
                                                    if let error = error {
                                                        log.error("Error al añadir el documento: \(error.localizedDescription)")
                                                    }
                                                }
                                                refPosicion.delete()
                                            }
                                        } else {
                                            log.error("El alumno no existe")
                                            self.nombreAlumno = "?"
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    log.info("Cola vacía")
                    self.nombreAlumno = self.codigoAula != "?" ? "" : "No hay conexión de red".localized()
                }
            }
        }
    }

    // MARK: - Buscar aula (invitado)

    func buscarAula(codigo: String?, pin: String?) {
        guard let codigo = codigo, let pin = pin else { return }
        log.debug("Buscando UID del aula: \(codigo):\(pin)")
        db.collectionGroup("aulas")
            .whereField("codigo", isEqualTo: codigo.uppercased())
            .whereField("pin", isEqualTo: pin)
            .getDocuments() { [weak self] (querySnapshot, error) in
                guard let self = self else { return }
                Task { @MainActor in
                    if let error = error {
                        log.error("Error al recuperar datos: \(error.localizedDescription)")
                        return
                    }
                    if let documents = querySnapshot?.documents, documents.count > 0 {
                        log.info("Aula encontrada: \(codigo)")
                        UserDefaults.standard.set(codigo, forKey: "codigoAulaConectada")
                        UserDefaults.standard.set(pin, forKey: "pinConectada")
                        self.desconectarListeners()
                        self.invitado = true
                        self.refAula = documents.first?.reference
                        self.conectarListener()
                    } else {
                        log.error("Aula no encontrada")
                        if UserDefaults.standard.string(forKey: "codigoAulaConectada") == nil {
                            self.alertaActiva = .errorConexion
                        }
                        self.desconectarAula()
                    }
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

    // MARK: - Borrar aula

    func borrarAulaReconectar(codigo: String) {
        mostrarIndicador = true
        desconectarListeners()
        refMisAulas?.whereField("codigo", isEqualTo: codigo.uppercased()).getDocuments() { [weak self] (querySnapshot, error) in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error {
                    log.error("Error al recuperar datos: \(error.localizedDescription)")
                    return
                }
                querySnapshot?.documents.first?.reference.delete() { [weak self] error in
                    guard let self = self else { return }
                    Task { @MainActor in
                        if let error = error {
                            log.error("Error al borrar el aula: \(error.localizedDescription)")
                        } else {
                            log.info("Aula borrada")
                            self.numAulas -= 1
                            if self.aulaActual == self.numAulas {
                                self.aulaActual = max(0, self.aulaActual - 1)
                            }
                            self.conectarAula(posicion: self.aulaActual)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actualizar etiqueta

    func actualizarEtiqueta(_ nuevaEtiqueta: String) {
        etiquetaAula = nuevaEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
        refAula?.updateData(["etiqueta": etiquetaAula]) { error in
            if let error = error {
                log.error("Error al actualizar el aula: \(error.localizedDescription)")
            } else {
                log.info("Aula actualizada")
            }
        }
    }

    // MARK: - Actualizar tiempo de espera

    func actualizarTiempoEspera(_ tiempo: Int) {
        tiempoEspera = tiempo
        log.info("Establecer tiempo de espera en \(tiempo) minutos...")
        refAula?.updateData(["espera": tiempo]) { error in
            if let error = error {
                log.error("Error al actualizar el aula: \(error.localizedDescription)")
            } else {
                log.info("Aula actualizada")
            }
        }
    }

    // MARK: - Navegación entre aulas

    func aulaAnterior() {
        if !invitado && numAulas > 1 && aulaActual > 0 {
            aulaActual -= 1
            log.debug("Aula anterior")
            desconectarListeners()
            conectarAula(posicion: aulaActual)
        }
    }

    func aulaSiguiente() {
        if !invitado && numAulas > 1 && aulaActual < numAulas - 1 {
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
        if sonidoActivado && recuentoAnterior == 0 && recuento == 1 {
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
