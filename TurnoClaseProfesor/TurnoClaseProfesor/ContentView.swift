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
// ContentView.swift
// TurnoClaseProfesor

import Localize_Swift
import SwiftUI
import TurnoClaseShared

// MARK: - Vista principal

struct ContentView: View {
    @StateObject private var vm = AulaViewModel()

    // Diálogos
    @State private var mostrarMenuAcciones = false
    @State private var mostrarDialogoConexion = false
    @State private var mostrarDialogoBorrar = false
    @State private var mostrarDialogoEtiqueta = false
    @State private var mostrarDialogoTiempo = false
    @State private var mostrarDialogoError = false
    @State private var mostrarListaCola = false

    // Campos de texto de los diálogos
    @State private var textoCodigo: String = ""
    @State private var textoPIN: String = ""
    @State private var textoEtiqueta: String = ""
    @State private var tiempoSeleccionado: Int = 5

    // Animación del botón siguiente
    @State private var opacidadBotonSiguiente: Double = 1.0

    var body: some View {
        PantallaPrincipal(
            vm: vm,
            opacidadBotonSiguiente: $opacidadBotonSiguiente,
            onMostrarMenu: { mostrarMenuAcciones = true },
            onMostrarCola: { mostrarListaCola = true }
        )
        .onAppear { vm.iniciar() }

        // MARK: - Menú de acciones (sheet nativo, evita bug de constraints en Catalyst)

        .sheet(isPresented: $mostrarMenuAcciones) {
            MenuAccionesAula(
                vm: vm,
                onEtiquetar: { textoEtiqueta = vm.etiquetaAula; mostrarDialogoEtiqueta = true },
                onTiempo: { tiempoSeleccionado = vm.tiempoEspera; mostrarDialogoTiempo = true },
                onConectar: { textoCodigo = ""; textoPIN = ""; mostrarDialogoConexion = true },
                onBorrar: { mostrarDialogoBorrar = true },
                onCerrar: { mostrarMenuAcciones = false }
            )
            .modify {
                if #available(iOS 16, *) {
                    $0.presentationDetents([.fraction(0.45)])
                        .presentationDragIndicator(.visible)
                } else {
                    $0
                }
            }
        }

        // MARK: - Diálogo confirmar borrado

        .alert("Borrar aula".localized(), isPresented: $mostrarDialogoBorrar) {
            Button("Ok".localized(), role: .destructive) {
                vm.borrarAulaReconectar(codigo: vm.codigoAula)
            }
            Button("Cancelar".localized(), role: .cancel) {}
        } message: {
            Text("Esta acción vaciará la cola de espera.".localized())
        }

        // MARK: - Diálogo error de conexión

        .alert("Error de conexión".localized(), isPresented: $mostrarDialogoError) {
            Button("Ok".localized()) {}
        } message: {
            Text("No se ha podido acceder al aula con los datos proporcionados.".localized())
        }
        .onChange(of: vm.alertaActiva?.id) { id in
            if id == AlertaAula.errorConexion.id {
                mostrarDialogoError = true
                vm.alertaActiva = nil
            }
        }

        // MARK: - Diálogo conectar a otra aula

        .sheet(isPresented: $mostrarDialogoConexion) {
            DialogoConexion(
                textoCodigo: $textoCodigo,
                textoPIN: $textoPIN,
                onConectar: { codigo, pin in
                    if vm.codigoAula != codigo {
                        vm.buscarAula(codigo: codigo, pin: pin)
                    } else {
                        mostrarDialogoError = true
                    }
                    mostrarDialogoConexion = false
                },
                onCancelar: { mostrarDialogoConexion = false }
            )
        }

        // MARK: - Diálogo etiquetar aula

        .sheet(isPresented: $mostrarDialogoEtiqueta) {
            DialogoEtiqueta(
                textoEtiqueta: $textoEtiqueta,
                onGuardar: { etiqueta in
                    vm.actualizarEtiqueta(etiqueta)
                    mostrarDialogoEtiqueta = false
                },
                onCancelar: { mostrarDialogoEtiqueta = false }
            )
        }

        // MARK: - Diálogo tiempo de espera

        .sheet(isPresented: $mostrarDialogoTiempo) {
            DialogoTiempoEspera(
                tiempos: vm.tiempos,
                tiempoActual: vm.tiempoEspera,
                onGuardar: { tiempo in
                    vm.actualizarTiempoEspera(tiempo)
                    mostrarDialogoTiempo = false
                },
                onCancelar: { mostrarDialogoTiempo = false }
            )
        }

        // MARK: - Lista de alumnos en cola

        .sheet(isPresented: $mostrarListaCola) {
            ListaColaAlumnos(vm: vm, onCerrar: { mostrarListaCola = false })
        }
    }
}

// MARK: - Botones circulares de acción para iOS 26

/// Botón circular con imagen de sistema, estilo iOS 26.
@available(iOS 26, *)
private struct BotonCircularAccion: View {
    let sistemaImagen: String
    var activo: Bool = true
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: sistemaImagen)
        }
        .buttonStyle(.plain)
        .opacity(activo ? 1.0 : 0.4)
        .disabled(!activo)
    }
}

// MARK: - Cabecera con icono para iOS 26

/// Cabecera estilo iOS 26: icono grande centrado + título debajo.
@available(iOS 26, *)
private struct CabeceraDialogo26: View {
    let sistemaImagen: String
    let colorIcono: Color
    let titulo: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(colorIcono.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: sistemaImagen)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(colorIcono)
            }
            Text(titulo)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Diálogo Conectar a otra aula

struct DialogoConexion: View {
    @Binding var textoCodigo: String
    @Binding var textoPIN: String
    let onConectar: (String, String) -> Void
    let onCancelar: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            DialogoConexion26(
                textoCodigo: $textoCodigo,
                textoPIN: $textoPIN,
                onConectar: onConectar,
                onCancelar: onCancelar
            )
        } else {
            DialogoConexionLegacy(
                textoCodigo: $textoCodigo,
                textoPIN: $textoPIN,
                onConectar: onConectar,
                onCancelar: onCancelar
            )
        }
    }
}

private struct DialogoConexionLegacy: View {
    @Binding var textoCodigo: String
    @Binding var textoPIN: String
    let onConectar: (String, String) -> Void
    let onCancelar: () -> Void

    var puedeConectar: Bool {
        textoCodigo.count >= 5 && textoPIN.count >= 4
    }

    var body: some View {
        NavigationView {
            VStack {
                Text("Conectar a otra aula".localized())
                    .font(.headline)
                Form {
                    Section {
                        TextField("Código de aula".localized(), text: $textoCodigo)
                            .autocapitalization(.allCharacters)
                            .autocorrectionDisabled(true)
                            .keyboardType(.asciiCapable)
                            .onChange(of: textoCodigo) { v in
                                if v.count > 5 { textoCodigo = String(v.prefix(5)) }
                            }
                            .onSubmit { if puedeConectar { onConectar(textoCodigo, textoPIN) } }
                        TextField("PIN".localized(), text: $textoPIN)
                            .keyboardType(.numberPad)
                            .onChange(of: textoPIN) { v in
                                if v.count > 4 { textoPIN = String(v.prefix(4)) }
                            }
                            .onSubmit { if puedeConectar { onConectar(textoCodigo, textoPIN) } }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar".localized()) { onCancelar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Conectar".localized()) {
                        onConectar(textoCodigo, textoPIN)
                    }
                    .disabled(!puedeConectar)
                }
            }
        }
    }
}

@available(iOS 26, *)
private struct DialogoConexion26: View {
    @Binding var textoCodigo: String
    @Binding var textoPIN: String
    let onConectar: (String, String) -> Void
    let onCancelar: () -> Void

    var puedeConectar: Bool {
        textoCodigo.count >= 5 && textoPIN.count >= 4
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CabeceraDialogo26(
                        sistemaImagen: "link.circle",
                        colorIcono: .azul,
                        titulo: "Conectar a otra aula".localized()
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Código de aula".localized(), text: $textoCodigo)
                        .autocapitalization(.allCharacters)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .onChange(of: textoCodigo) { v in
                            if v.count > 5 { textoCodigo = String(v.prefix(5)) }
                        }
                        .onSubmit { if puedeConectar { onConectar(textoCodigo, textoPIN) } }
                    TextField("PIN".localized(), text: $textoPIN)
                        .keyboardType(.numberPad)
                        .onChange(of: textoPIN) { v in
                            if v.count > 4 { textoPIN = String(v.prefix(4)) }
                        }
                        .onSubmit { if puedeConectar { onConectar(textoCodigo, textoPIN) } }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BotonCircularAccion(
                        sistemaImagen: "xmark",
                        accion: onCancelar
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    BotonCircularAccion(
                        sistemaImagen: "checkmark",
                        activo: puedeConectar,
                        accion: {
                            if puedeConectar { onConectar(textoCodigo, textoPIN) }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Diálogo Etiquetar aula

struct DialogoEtiqueta: View {
    @Binding var textoEtiqueta: String
    let onGuardar: (String) -> Void
    let onCancelar: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            DialogoEtiqueta26(
                textoEtiqueta: $textoEtiqueta,
                onGuardar: onGuardar,
                onCancelar: onCancelar
            )
        } else {
            DialogoEtiquetaLegacy(
                textoEtiqueta: $textoEtiqueta,
                onGuardar: onGuardar,
                onCancelar: onCancelar
            )
        }
    }
}

private struct DialogoEtiquetaLegacy: View {
    @Binding var textoEtiqueta: String
    let onGuardar: (String) -> Void
    let onCancelar: () -> Void

    var puedeGuardar: Bool {
        textoEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            || textoEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines).count == 0
    }

    var body: some View {
        NavigationView {
            VStack {
                Text("Etiquetar aula".localized())
                    .font(.headline)
                Form {
                    Section {
                        TextField("Etiqueta".localized(), text: $textoEtiqueta)
                            .autocapitalization(.sentences)
                            .keyboardType(.asciiCapable)
                            .onChange(of: textoEtiqueta) { v in
                                if v.count > 50 { textoEtiqueta = String(v.prefix(50)) }
                            }
                            .onSubmit { if puedeGuardar { onGuardar(textoEtiqueta) } }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar".localized()) { onCancelar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar".localized()) {
                        onGuardar(textoEtiqueta)
                    }
                    .disabled(!puedeGuardar)
                }
            }
        }
    }
}

@available(iOS 26, *)
private struct DialogoEtiqueta26: View {
    @Binding var textoEtiqueta: String
    let onGuardar: (String) -> Void
    let onCancelar: () -> Void

    var puedeGuardar: Bool {
        textoEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            || textoEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines).count == 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CabeceraDialogo26(
                        sistemaImagen: "tag",
                        colorIcono: .azul,
                        titulo: "Etiquetar aula".localized()
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Etiqueta".localized(), text: $textoEtiqueta)
                        .autocapitalization(.sentences)
                        .keyboardType(.asciiCapable)
                        .onChange(of: textoEtiqueta) { v in
                            if v.count > 50 { textoEtiqueta = String(v.prefix(50)) }
                        }
                        .onSubmit { if puedeGuardar { onGuardar(textoEtiqueta) } }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BotonCircularAccion(
                        sistemaImagen: "xmark",
                        accion: onCancelar
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    BotonCircularAccion(
                        sistemaImagen: "checkmark",
                        activo: puedeGuardar,
                        accion: {
                            if puedeGuardar { onGuardar(textoEtiqueta) }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Diálogo Tiempo de espera

struct DialogoTiempoEspera: View {
    let tiempos: [Int]
    let tiempoActual: Int
    let onGuardar: (Int) -> Void
    let onCancelar: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            DialogoTiempoEspera26(
                tiempos: tiempos,
                tiempoActual: tiempoActual,
                onGuardar: onGuardar,
                onCancelar: onCancelar
            )
        } else {
            DialogoTiempoEsperaLegacy(
                tiempos: tiempos,
                tiempoActual: tiempoActual,
                onGuardar: onGuardar,
                onCancelar: onCancelar
            )
        }
    }
}

private struct DialogoTiempoEsperaLegacy: View {
    let tiempos: [Int]
    let tiempoActual: Int
    let onGuardar: (Int) -> Void
    let onCancelar: () -> Void

    @State private var seleccion: Int

    init(tiempos: [Int], tiempoActual: Int, onGuardar: @escaping (Int) -> Void, onCancelar: @escaping () -> Void) {
        self.tiempos = tiempos
        self.tiempoActual = tiempoActual
        self.onGuardar = onGuardar
        self.onCancelar = onCancelar
        _seleccion = State(initialValue: tiempoActual)
    }

    var body: some View {
        NavigationView {
            VStack {
                Text("Tiempo de espera (minutos)".localized())
                    .font(.headline)
                Form {
                    Picker("Tiempo de espera (minutos)".localized(), selection: $seleccion) {
                        ForEach(tiempos, id: \.self) { t in
                            Text("\(t)").tag(t)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar".localized()) { onCancelar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar".localized()) {
                        onGuardar(seleccion)
                    }
                }
            }
        }
    }
}

@available(iOS 26, *)
private struct DialogoTiempoEspera26: View {
    let tiempos: [Int]
    let tiempoActual: Int
    let onGuardar: (Int) -> Void
    let onCancelar: () -> Void

    @State private var seleccion: Int

    init(tiempos: [Int], tiempoActual: Int, onGuardar: @escaping (Int) -> Void, onCancelar: @escaping () -> Void) {
        self.tiempos = tiempos
        self.tiempoActual = tiempoActual
        self.onGuardar = onGuardar
        self.onCancelar = onCancelar
        _seleccion = State(initialValue: tiempoActual)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CabeceraDialogo26(
                        sistemaImagen: "timer",
                        colorIcono: .azul,
                        titulo: "Tiempo de espera (minutos)".localized()
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("", selection: $seleccion) {
                        ForEach(tiempos, id: \.self) { t in
                            Text("\(t)").tag(t)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 180)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BotonCircularAccion(
                        sistemaImagen: "xmark",
                        accion: onCancelar
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    BotonCircularAccion(
                        sistemaImagen: "checkmark",
                        accion: { onGuardar(seleccion) }
                    )
                }
            }
        }
    }
}

// MARK: - Menú de acciones del aula (reemplaza confirmationDialog)

private struct MenuAccionesAula: View {
    @ObservedObject var vm: AulaViewModel
    let onEtiquetar: () -> Void
    let onTiempo: () -> Void
    let onConectar: () -> Void
    let onBorrar: () -> Void
    let onCerrar: () -> Void

    var titulo: String {
        guard vm.codigoAula != "?" else { return "No hay conexión de red".localized() }
        return vm.invitado
            ? "Conectado como invitado".localized()
            : String(format: "PIN para compartir este aula: %@".localized(), vm.PIN)
    }

    var subtitulo: String {
        guard vm.codigoAula != "?" else { return "Error de conexión".localized() }
        return String(format: "Aula %@".localized(), vm.codigoAula)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cabecera informativa
            VStack(spacing: 4) {
                Text(subtitulo)
                    .font(.headline)
                Text(titulo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            .padding(.horizontal, 20)

            Divider()

            // Acciones
            List {
                if !vm.invitado, vm.codigoAula != "?" {
                    Button {
                        onCerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onEtiquetar() }
                    } label: {
                        Label {
                            if vm.etiquetaAula.count > 0 {
                                Text(String(format: "» %@ «", vm.etiquetaAula))
                                    .fontWeight(.bold)
                            } else {
                                Text("Etiquetar aula".localized())
                            }
                        } icon: {
                            Image(systemName: "tag")
                                .foregroundColor(.azul)
                        }
                    }

                    Button {
                        onCerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onTiempo() }
                    } label: {
                        Label {
                            Text(String(format: "Tiempo de espera: %d minutos".localized(), vm.tiempoEspera))
                        } icon: {
                            Image(systemName: "timer")
                                .foregroundColor(.azul)
                        }
                    }

                    if vm.numAulas < vm.MAX_AULAS {
                        Button {
                            onCerrar(); vm.anyadirAula()
                        } label: {
                            Label {
                                Text("Añadir aula".localized())
                            } icon: {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.azul)
                            }
                        }
                    }

                    if vm.numAulas > 1 {
                        Button(role: .destructive) {
                            onCerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onBorrar() }
                        } label: {
                            Label {
                                Text("Borrar aula".localized())
                            } icon: {
                                Image(systemName: "trash")
                            }
                            .foregroundColor(.rojo)
                        }
                    }

                    Button {
                        onCerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onConectar() }
                    } label: {
                        Label {
                            Text("Conectar a otra aula".localized())
                        } icon: {
                            Image(systemName: "link.circle")
                                .foregroundColor(.azul)
                        }
                    }
                } else if vm.invitado {
                    Button(role: .destructive) {
                        onCerrar(); vm.desconectarAula()
                    } label: {
                        Label {
                            Text("Desconectar del aula".localized())
                        } icon: {
                            Image(systemName: "xmark.circle")
                        }
                        .foregroundColor(.rojo)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Pantalla principal (layout visual)

private struct PantallaPrincipal: View {
    @ObservedObject var vm: AulaViewModel
    @Binding var opacidadBotonSiguiente: Double
    let onMostrarMenu: () -> Void
    let onMostrarCola: () -> Void

    var body: some View {
        GeometryReader { geo in
            let tamanyoCirculoPrincipal: CGFloat = min(geo.size.width, geo.size.height) * 0.70
            let tamanyoBoton: CGFloat = 72
            let centroX = geo.size.width / 2 + 8
            let centroY = geo.size.height / 2 - 12
            let radio = tamanyoCirculoPrincipal / 2

            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                // Círculo principal amarillo
                ZStack {
                    Image.persona
                        .resizable()
                        .scaledToFit()
                        .frame(width: tamanyoCirculoPrincipal * 0.60,
                               height: tamanyoCirculoPrincipal * 0.60)
                        .foregroundColor(.black)
                        .opacity(0.025)

                    Group {
                        if vm.cargando {
                            AnimacionPuntos(color: .black, tamanyo: 10)
                        } else if vm.errorRed {
                            Text("No hay conexión de red".localized())
                                .font(.system(size: 22))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.black)
                                .padding(.horizontal, 20)
                        } else {
                            Text(vm.nombreAlumno)
                                .font(.system(size: 51))
                                .minimumScaleFactor(0.2)
                                .lineLimit(1)
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: tamanyoCirculoPrincipal - 32)
                        }
                    }
                }
                .frame(width: tamanyoCirculoPrincipal, height: tamanyoCirculoPrincipal)
                .background(Circle().foregroundColor(.amarillo))
                .position(x: centroX, y: centroY)
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            if value.translation.width < -30 { vm.aulaSiguiente() }
                            else if value.translation.width > 30 { vm.aulaAnterior() }
                        }
                )

                // Botón código de aula (gris, -60°)
                BotónCircular(
                    titulo: vm.codigoAula,
                    colorFondo: .gris,
                    colorTexto: .black,
                    tamanyo: tamanyoBoton
                ) {
                    vm.feedbackTactilLigero()
                    onMostrarMenu()
                }
                .position(posicionEnBorde(angulo: -60, centroX: centroX, centroY: centroY, radio: radio))
                .accessibilityIdentifier("botonCodigoAula")

                // Botón número en cola (rojo, 30°)
                BotónCircular(
                    titulo: "\(vm.enCola)",
                    colorFondo: .rojo,
                    colorTexto: .white,
                    tamanyo: tamanyoBoton
                ) {
                    vm.feedbackTactilLigero()
                    onMostrarCola()
                }
                .position(posicionEnBorde(angulo: 30, centroX: centroX, centroY: centroY, radio: radio))
                .accessibilityIdentifier("botonEnCola")

                // Botón siguiente (azul, 150°)
                // Cuando hay error de red: muestra icono de recargar y permite reintentar
                if vm.errorRed {
                    BotónCircularIcono(
                        imagen: .recargar,
                        colorFondo: .azul,
                        colorIcono: .white,
                        tamanyo: tamanyoBoton
                    ) {
                        vm.feedbackTactilLigero()
                        vm.reintentar()
                    }
                    .position(posicionEnBorde(angulo: 150, centroX: centroX, centroY: centroY, radio: radio))
                    .accessibilityIdentifier("botonSiguiente")
                } else {
                    BotónCircularIcono(
                        imagen: .flecha,
                        colorFondo: .azul,
                        colorIcono: .white,
                        tamanyo: tamanyoBoton
                    ) {
                        vm.feedbackTactilLigero()
                        vm.mostrarSiguiente(avanzarCola: true)
                    }
                    .opacity(opacidadBotonSiguiente)
                    ._onButtonGesture(pressing: { pressing in
                        guard !vm.cargando else { return }
                        withAnimation(.linear(duration: pressing ? 0.1 : 0.3)) {
                            opacidadBotonSiguiente = pressing ? 0.15 : 1.0
                        }
                    }, perform: {})
                    .position(posicionEnBorde(angulo: 150, centroX: centroX, centroY: centroY, radio: radio))
                    .accessibilityIdentifier("botonSiguiente")
                }

                // PageControl + ActivityIndicator
                VStack(spacing: 8) {
                    if vm.mostrarIndicador {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else if vm.numAulas > 1 && !vm.invitado {
                        PageControlView(currentPage: vm.aulaActual, totalPages: vm.numAulas)
                            .frame(height: 26)
                    }
                }
                .frame(width: 243)
                .position(x: centroX, y: centroY + tamanyoCirculoPrincipal / 2 + 40)
            }
        }
    }
}

// MARK: - Lista de alumnos en cola

struct ListaColaAlumnos: View {
    @ObservedObject var vm: AulaViewModel
    let onCerrar: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            ListaColaAlumnos26(vm: vm, onCerrar: onCerrar)
        } else {
            ListaColaAlumnosLegacy(vm: vm, onCerrar: onCerrar)
        }
    }
}

private struct ListaColaAlumnosLegacy: View {
    @ObservedObject var vm: AulaViewModel
    let onCerrar: () -> Void

    var body: some View {
        NavigationView {
            Group {
                if vm.alumnosEnCola.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("La cola está vacía".localized())
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(vm.alumnosEnCola.enumerated()), id: \.element.id) { index, alumno in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().foregroundColor(index == 0 ? .azul : .gris))
                                Text(alumno.nombre)
                                    .font(.body)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                vm.eliminarAlumnoDeCola(vm.alumnosEnCola[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cola de espera".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar".localized()) { onCerrar() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !vm.alumnosEnCola.isEmpty {
                        EditButton()
                    }
                }
            }
        }
    }
}

@available(iOS 26, *)
private struct ListaColaAlumnos26: View {
    @ObservedObject var vm: AulaViewModel
    let onCerrar: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if vm.alumnosEnCola.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("La cola está vacía".localized())
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(vm.alumnosEnCola.enumerated()), id: \.element.id) { index, alumno in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().foregroundColor(index == 0 ? .azul : .gris))
                                Text(alumno.nombre)
                                    .font(.body)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                vm.eliminarAlumnoDeCola(vm.alumnosEnCola[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cola de espera".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BotonCircularAccion(sistemaImagen: "xmark", accion: onCerrar)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !vm.alumnosEnCola.isEmpty {
                        EditButton()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
