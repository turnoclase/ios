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
// ConexionViewModel.swift
// TurnoClase

import AudioToolbox
import Combine
import Foundation
import SwiftUI

import FirebaseAuth
import FirebaseFirestore

import TurnoClaseShared

// MARK: - Estado de la pantalla de turno

enum EstadoTurno {
    case enCola(posicion: Int)
    case esTuTurno
    case volverAEmpezar
    case esperando(segundosRestantes: Int)
    case error(mensaje: String)
}

// MARK: - ViewModel

@MainActor
class ConexionViewModel: ObservableObject {
    // MARK: Datos de entrada (pantalla inicial)

    @Published var codigoAula: String = ""
    @Published var nombreUsuario: String = ""
    @Published var placeholder: String = ""

    // MARK: Estado de navegación

    @Published var mostrandoTurno: Bool = false

    // MARK: Estado pantalla de turno

    @Published var codigoAulaActual: String = ""
    @Published var estadoTurno: EstadoTurno = .enCola(posicion: 0)

    // Cronómetro
    @Published var minutosRestantes: Int = 0
    @Published var segundosRestantes: Int = 0
    @Published var mostrarCronometro: Bool = false
    @Published var mostrarBotonActualizar: Bool = false
    @Published var mostrarError: Bool = false

    // MARK: Propiedades internas

    var uid: String?
    var refAula: DocumentReference?
    var refPosicion: DocumentReference?
    var listenerAula: ListenerRegistration?
    var listenerCola: ListenerRegistration?
    var listenerPosicion: ListenerRegistration?
    var pedirTurno = true
    var atendido = false
    var timer: Timer?
    var ultimaPeticion: Date?
    var segundosEspera = 300 // 5 minutos por defecto
    var n = 2 // Para Fastlane snapshot

    // MARK: - Inicialización (pantalla inicial)

    func iniciar() {
        placeholder = Nombres.aleatorio()
        codigoAula = UserDefaults.standard.string(forKey: "codigoAula") ?? ""
        nombreUsuario = UserDefaults.standard.string(forKey: "nombreUsuario") ?? ""

        #if DEBUG
        if codigoAula.isEmpty {
            codigoAula = "BE131"
            nombreUsuario = placeholder
        }
        #endif
    }

    var puedeConectar: Bool {
        codigoAula.count >= 5 && nombreEfectivo.count >= 2
    }

    var nombreEfectivo: String {
        nombreUsuario.isEmpty ? placeholder : nombreUsuario
    }

    // MARK: - Conectar al aula (botón siguiente en pantalla inicial)

    func conectar() {
        let codigo = codigoAula.uppercased()
        let nombre = nombreEfectivo

        UserDefaults.standard.set(codigo, forKey: "codigoAula")
        UserDefaults.standard.set(nombre, forKey: "nombreUsuario")

        codigoAulaActual = codigo

        if UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT") {
            codigoAulaActual = "BE131"
            estadoTurno = .enCola(posicion: 2)
            mostrandoTurno = true
            return
        }

        Task {
            do {
                let resultado = try await Auth.auth().signInAnonymously()
                uid = resultado.user.uid
                log.info("Registrado como usuario con UID: \(uid ??? "[Desconocido]")")
                actualizarAlumno(nombre: nombre)
                encolarAlumno(codigo: codigo)
                mostrandoTurno = true
            } catch {
                log.error("Error de inicio de sesión: \(error.localizedDescription)")
                estadoTurno = .error(mensaje: NSLocalizedString("MENSAJE_ERROR", comment: ""))
                mostrandoTurno = true
            }
        }
    }

    // MARK: - Registrar alumno en Firestore

    private func actualizarAlumno(nombre: String) {
        guard let uid = uid else { return }
        Task {
            do {
                try await db.collection("alumnos").document(uid).setData(["nombre": nombre], merge: true)
                log.info("Alumno actualizado")
            } catch {
                log.error("Error al actualizar el alumno: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Buscar aula y encolar

    func encolarAlumno(codigo: String) {
        Task {
            do {
                let querySnapshot = try await db.collectionGroup("aulas")
                    .whereField("codigo", isEqualTo: codigo)
                    .limit(to: 1)
                    .getDocuments()
                if let doc = querySnapshot.documents.first {
                    log.info("Conectado a aula existente")
                    conectarListenerAula(doc)
                } else {
                    log.error("Aula no encontrada")
                    estadoTurno = .error(mensaje: NSLocalizedString("MENSAJE_ERROR", comment: ""))
                    actualizarUI()
                }
            } catch {
                log.error("Error al recuperar datos: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Listeners

    private func conectarListenerAula(_ document: QueryDocumentSnapshot) {
        guard listenerAula == nil else { return }
        listenerAula = document.reference.addSnapshotListener { [weak self] documentSnapshot, _ in
            guard let self = self else { return }
            Task { @MainActor in
                if documentSnapshot?.exists == true,
                   documentSnapshot?.data()?["codigo"] as? String == self.codigoAulaActual
                {
                    self.refAula = documentSnapshot?.reference
                    self.segundosEspera = ((documentSnapshot?.data()?["espera"] as? Int) ?? 5) * 60
                    self.conectarListenerCola()
                } else {
                    log.info("El aula ha desaparecido")
                    self.desconectarListeners()
                    self.abandonarCola()
                }
            }
        }
    }

    private func conectarListenerCola() {
        guard listenerCola == nil, let refAula = refAula else { return }
        listenerCola = refAula.collection("cola").addSnapshotListener { [weak self] _, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error {
                    log.error("Error al recuperar datos: \(error.localizedDescription)")
                } else {
                    self.buscarAlumnoEnCola()
                }
            }
        }
    }

    private func conectarListenerPosicion(_ refPos: DocumentReference) {
        guard listenerPosicion == nil else { return }
        listenerPosicion = refPos.addSnapshotListener { [weak self] documentSnapshot, _ in
            guard let self = self else { return }
            Task { @MainActor in
                if documentSnapshot?.exists == false {
                    self.atendido = true
                    log.info("Nos han borrado de la cola")
                }
            }
        }
    }

    // MARK: - Lógica de cola

    private func buscarAlumnoEnCola() {
        guard let uid = uid, let refAula = refAula else { return }
        Task {
            do {
                let resultados = try await refAula.collection("cola")
                    .whereField("alumno", isEqualTo: uid)
                    .limit(to: 1)
                    .getDocuments()
                procesarCola(resultados)
            } catch {
                log.error("Error al recuperar datos: \(error.localizedDescription)")
            }
        }
    }

    private func procesarCola(_ querySnapshot: QuerySnapshot) {
        guard let refAula = refAula, let uid = uid else { return }
        let docs = querySnapshot.documents

        if pedirTurno, docs.isEmpty {
            pedirTurno = false
            log.info("Alumno no encontrado, lo añadimos")
            Task {
                await recuperarUltimaPeticion()
                if !(tiempoEsperaRestante() > 0) {
                    mostrarCronometro = false
                    mostrarBotonActualizar = false
                    mostrarError = false
                    reiniciarCronometro()
                    borrarUltimaPeticion()
                    do {
                        let ref = try await refAula.collection("cola").addDocument(data: [
                            "alumno": uid,
                            "timestamp": FieldValue.serverTimestamp(),
                        ])
                        refPosicion = ref
                        conectarListenerPosicion(ref)
                        actualizarPantalla()
                    } catch {
                        log.error("Error al añadir el documento: \(error.localizedDescription)")
                    }
                } else {
                    estadoTurno = .esperando(segundosRestantes: tiempoEsperaRestante())
                    mostrarCronometro = true
                    mostrarBotonActualizar = false
                    mostrarError = false
                    iniciarCronometro()
                    actualizarUI()
                }
            }
        } else if !docs.isEmpty {
            log.info("Alumno encontrado, ya está en la cola")
            refPosicion = docs[0].reference
            conectarListenerPosicion(docs[0].reference)
            actualizarPantalla()
        } else {
            log.info("La cola se ha vaciado")
            Task {
                await recuperarUltimaPeticion()
                if tiempoEsperaRestante() > 0 {
                    // Hay que esperar: mostrar cronómetro
                    estadoTurno = .esperando(segundosRestantes: tiempoEsperaRestante())
                    mostrarCronometro = true
                    mostrarBotonActualizar = false
                    mostrarError = false
                    iniciarCronometro()
                    actualizarUI()
                } else {
                    // No hay tiempo de espera: pedir turno automáticamente
                    log.info("Sin tiempo de espera, pidiendo turno automáticamente")
                    reiniciarCronometro()
                    borrarUltimaPeticion()
                    atendido = false
                    pedirTurno = true
                    do {
                        let ref = try await refAula.collection("cola").addDocument(data: [
                            "alumno": uid,
                            "timestamp": FieldValue.serverTimestamp(),
                        ])
                        refPosicion = ref
                        desconectarListenerPosicion()
                        conectarListenerPosicion(ref)
                        actualizarPantalla()
                    } catch {
                        log.error("Error al añadir el documento: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func actualizarPantalla() {
        guard let refAula = refAula, let refPosicion = refPosicion else {
            estadoTurno = .error(mensaje: NSLocalizedString("MENSAJE_ERROR", comment: ""))
            actualizarUI()
            return
        }
        Task {
            do {
                let document = try await refPosicion.getDocument()
                guard let datos = document.data(),
                      let timestamp = datos["timestamp"] as? Timestamp else { return }
                let querySnapshot = try await refAula.collection("cola")
                    .whereField("timestamp", isLessThanOrEqualTo: timestamp)
                    .getDocuments()
                let posicion = querySnapshot.documents.count
                log.info("Posición en la cola: \(posicion)")
                if posicion > 1 {
                    estadoTurno = .enCola(posicion: posicion - 1)
                } else if posicion == 1 {
                    estadoTurno = .esTuTurno
                }
                actualizarUI()
            } catch {
                log.error("Error al actualizar pantalla: \(error.localizedDescription)")
            }
        }
    }

    private func actualizarUI() {
        switch estadoTurno {
        case .esperando:
            mostrarCronometro = true
            mostrarBotonActualizar = false
            mostrarError = false
        case .error:
            mostrarCronometro = false
            mostrarBotonActualizar = false
            mostrarError = true
        default:
            mostrarCronometro = false
            mostrarBotonActualizar = false
            mostrarError = false
        }
    }

    // MARK: - Botones de la pantalla de turno

    func cancelar() {
        log.info("Cancelando...")
        reiniciarCronometro()
        desconectarListeners()
        abandonarCola()
    }

    func actualizar() {
        if UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT") {
            if n > 0 { estadoTurno = .enCola(posicion: n) }
            else if n == 0 { estadoTurno = .esTuTurno }
            else { estadoTurno = .volverAEmpezar }
            n -= 1
            return
        }
        if atendido {
            log.info("Pidiendo nuevo turno")
            desconectarListeners()
            atendido = false
            pedirTurno = true
            encolarAlumno(codigo: codigoAulaActual)
        } else {
            log.info("Ya tenemos turno")
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Abandono de cola

    private func abandonarCola() {
        Task {
            do {
                if let refPosicion = refPosicion {
                    try await refPosicion.delete()
                }
            } catch {
                log.error("Error al abandonar la cola: \(error.localizedDescription)")
            }
            mostrandoTurno = false
        }
    }

    func desconectarListeners() {
        listenerAula?.remove(); listenerAula = nil
        listenerCola?.remove(); listenerCola = nil
        listenerPosicion?.remove(); listenerPosicion = nil
    }

    private func desconectarListenerPosicion() {
        listenerPosicion?.remove()
        listenerPosicion = nil
    }

    // MARK: - Cronómetro

    func iniciarCronometro() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickCronometro()
            }
        }
    }

    func reiniciarCronometro() {
        timer?.invalidate()
        timer = nil
    }

    private func tiempoEsperaRestante() -> Int {
        guard let ultimaPeticion = ultimaPeticion else { return -1 }
        return segundosEspera - Int(Date().timeIntervalSince(ultimaPeticion))
    }

    private func tickCronometro() {
        let restante = tiempoEsperaRestante()
        if restante >= 0 {
            minutosRestantes = restante / 60
            segundosRestantes = restante % 60
        } else {
            // El tiempo de espera ha expirado: mostrar mensaje y dejar que el usuario pulse el botón
            reiniciarCronometro()
            borrarUltimaPeticion()
            estadoTurno = .volverAEmpezar
            mostrarCronometro = false
            mostrarBotonActualizar = true
            mostrarError = false
            atendido = true
        }
    }

    // MARK: - Última petición (tiempo de espera)

    private func recuperarUltimaPeticion() async {
        guard let uid = uid, let refAula = refAula else { return }
        do {
            let document = try await refAula.collection("espera").document(uid).getDocument()
            if let datos = document.data(), let stamp = datos["timestamp"] as? Timestamp {
                ultimaPeticion = stamp.dateValue()
            }
        } catch {
            log.error("Error al recuperar última petición: \(error.localizedDescription)")
        }
    }

    private func borrarUltimaPeticion() {
        ultimaPeticion = nil
        guard let uid = uid, let refAula = refAula else { return }
        Task {
            do {
                try await refAula.collection("espera").document(uid).delete()
            } catch {
                log.error("Error al borrar última petición: \(error.localizedDescription)")
            }
        }
    }
}
