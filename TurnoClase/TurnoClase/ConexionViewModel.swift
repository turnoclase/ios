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

import Foundation
import Combine
import SwiftUI
import AudioToolbox

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
    var segundosEspera = 300  // 5 minutos por defecto
    var n = 2  // Para Fastlane snapshot

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

        Auth.auth().signInAnonymously() { [weak self] (result, error) in
            guard let self = self else { return }
            Task { @MainActor in
                if let resultado = result {
                    self.uid = resultado.user.uid
                    log.info("Registrado como usuario con UID: \(self.uid ??? "[Desconocido]")")
                    self.actualizarAlumno(nombre: nombre)
                    self.encolarAlumno(codigo: codigo)
                    self.mostrandoTurno = true
                } else {
                    log.error("Error de inicio de sesión: \(error!.localizedDescription)")
                    self.estadoTurno = .error(mensaje: NSLocalizedString("MENSAJE_ERROR", comment: ""))
                    self.mostrandoTurno = true
                }
            }
        }
    }

    // MARK: - Registrar alumno en Firestore

    private func actualizarAlumno(nombre: String) {
        guard let uid = uid else { return }
        db.collection("alumnos").document(uid).setData(["nombre": nombre], merge: true) { error in
            if let error = error {
                log.error("Error al actualizar el alumno: \(error.localizedDescription)")
            } else {
                log.info("Alumno actualizado")
            }
        }
    }

    // MARK: - Buscar aula y encolar

    func encolarAlumno(codigo: String) {
        db.collectionGroup("aulas")
            .whereField("codigo", isEqualTo: codigo)
            .limit(to: 1)
            .getDocuments() { [weak self] (querySnapshot, error) in
                guard let self = self else { return }
                Task { @MainActor in
                    if let error = error {
                        log.error("Error al recuperar datos: \(error.localizedDescription)")
                        return
                    }
                    if let doc = querySnapshot?.documents.first {
                        log.info("Conectado a aula existente")
                        self.conectarListenerAula(doc)
                    } else {
                        log.error("Aula no encontrada")
                        self.estadoTurno = .error(mensaje: NSLocalizedString("MENSAJE_ERROR", comment: ""))
                        self.actualizarUI()
                    }
                }
            }
    }

    // MARK: - Listeners

    private func conectarListenerAula(_ document: QueryDocumentSnapshot) {
        guard listenerAula == nil else { return }
        listenerAula = document.reference.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            Task { @MainActor in
                if documentSnapshot?.exists == true,
                   documentSnapshot?.data()?["codigo"] as? String == self.codigoAulaActual {
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
        refAula.collection("cola")
            .whereField("alumno", isEqualTo: uid)
            .limit(to: 1)
            .getDocuments() { [weak self] (resultados, error) in
                guard let self = self else { return }
                Task { @MainActor in
                    if let error = error {
                        log.error("Error al recuperar datos: \(error.localizedDescription)")
                    } else {
                        self.procesarCola(resultados)
                    }
                }
            }
    }

    private func procesarCola(_ querySnapshot: QuerySnapshot?) {
        guard let refAula = refAula, let uid = uid else { return }
        let docs = querySnapshot?.documents ?? []

        if pedirTurno && docs.isEmpty {
            pedirTurno = false
            log.info("Alumno no encontrado, lo añadimos")
            recuperarUltimaPeticion {
                if !(self.tiempoEsperaRestante() > 0) {
                    self.mostrarBotonActualizar = true
                    self.mostrarCronometro = false
                    self.mostrarError = false
                    self.reiniciarCronometro()
                    self.borrarUltimaPeticion()
                    self.refPosicion = refAula.collection("cola").addDocument(data: [
                        "alumno": uid,
                        "timestamp": FieldValue.serverTimestamp()
                    ]) { error in
                        if let error = error {
                            log.error("Error al añadir el documento: \(error.localizedDescription)")
                        } else {
                            if let ref = self.refPosicion {
                                self.conectarListenerPosicion(ref)
                            }
                            self.actualizarPantalla()
                        }
                    }
                } else {
                    self.estadoTurno = .esperando(segundosRestantes: self.tiempoEsperaRestante())
                    self.mostrarCronometro = true
                    self.mostrarBotonActualizar = false
                    self.mostrarError = false
                    self.iniciarCronometro()
                    self.actualizarUI()
                }
            }
        } else if !docs.isEmpty {
            log.info("Alumno encontrado, ya está en la cola")
            refPosicion = docs[0].reference
            conectarListenerPosicion(docs[0].reference)
            actualizarPantalla()
        } else {
            log.info("La cola se ha vaciado")
            recuperarUltimaPeticion {
                if self.atendido && !(self.tiempoEsperaRestante() > 0) {
                    self.estadoTurno = .volverAEmpezar
                    self.mostrarBotonActualizar = true
                    self.mostrarCronometro = false
                    self.mostrarError = false
                    self.reiniciarCronometro()
                    self.borrarUltimaPeticion()
                } else {
                    self.estadoTurno = .esperando(segundosRestantes: self.tiempoEsperaRestante())
                    self.mostrarCronometro = true
                    self.mostrarBotonActualizar = false
                    self.mostrarError = false
                    self.iniciarCronometro()
                }
                self.actualizarUI()
            }
        }
    }

    private func actualizarPantalla() {
        guard let refAula = refAula, let refPosicion = refPosicion else {
            estadoTurno = .error(mensaje: NSLocalizedString("MENSAJE_ERROR", comment: ""))
            actualizarUI()
            return
        }
        refPosicion.getDocument { [weak self] (document, _) in
            guard let self = self else { return }
            Task { @MainActor in
                if let datos = document?.data(), let timestamp = datos["timestamp"] as? Timestamp {
                    refAula.collection("cola")
                        .whereField("timestamp", isLessThanOrEqualTo: timestamp)
                        .getDocuments() { [weak self] (querySnapshot, _) in
                            guard let self = self else { return }
                            Task { @MainActor in
                                let posicion = querySnapshot?.documents.count ?? 0
                                log.info("Posición en la cola: \(posicion)")
                                if posicion > 1 {
                                    self.estadoTurno = .enCola(posicion: posicion - 1)
                                } else if posicion == 1 {
                                    self.estadoTurno = .esTuTurno
                                }
                                self.actualizarUI()
                            }
                        }
                }
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
            mostrarBotonActualizar = true
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
        if let refPosicion = refPosicion {
            refPosicion.delete() { [weak self] _ in
                Task { @MainActor in
                    self?.mostrandoTurno = false
                }
            }
        } else {
            mostrandoTurno = false
        }
    }

    func desconectarListeners() {
        listenerAula?.remove(); listenerAula = nil
        listenerCola?.remove(); listenerCola = nil
        listenerPosicion?.remove(); listenerPosicion = nil
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
            reiniciarCronometro()
            borrarUltimaPeticion()
            estadoTurno = .volverAEmpezar
            atendido = true
            mostrarBotonActualizar = true
            mostrarCronometro = false
        }
    }

    // MARK: - Última petición (tiempo de espera)

    private func recuperarUltimaPeticion(completado: @escaping () -> Void) {
        guard let uid = uid, let refAula = refAula else { completado(); return }
        refAula.collection("espera").document(uid).getDocument() { [weak self] (document, error) in
            guard let self = self else { return }
            Task { @MainActor in
                if let datos = document?.data(), let stamp = datos["timestamp"] as? Timestamp {
                    self.ultimaPeticion = stamp.dateValue()
                }
                completado()
            }
        }
    }

    private func borrarUltimaPeticion() {
        ultimaPeticion = nil
        guard let uid = uid, let refAula = refAula else { return }
        refAula.collection("espera").document(uid).delete() { error in
            if let error = error {
                log.error("Error al borrar última petición: \(error.localizedDescription)")
            }
        }
    }
}
