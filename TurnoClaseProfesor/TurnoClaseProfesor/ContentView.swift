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
            onMostrarMenu: { mostrarMenuAcciones = true }
        )
        .onAppear { vm.iniciar() }

        // MARK: - Menú de acciones (sheet nativo, evita bug de constraints en Catalyst)

        .sheet(isPresented: $mostrarMenuAcciones) {
            MenuAccionesAula(
                vm: vm,
                onEtiquetar: { textoEtiqueta = ""; mostrarDialogoEtiqueta = true },
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
    }
}

// MARK: - Diálogo Conectar a otra aula

struct DialogoConexion: View {
    @Binding var textoCodigo: String
    @Binding var textoPIN: String
    let onConectar: (String, String) -> Void
    let onCancelar: () -> Void

    var puedeConectar: Bool {
        textoCodigo.count >= 5 && textoPIN.count >= 4
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Código de aula".localized(), text: $textoCodigo)
                        .autocapitalization(.allCharacters)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .onChange(of: textoCodigo) { v in
                            if v.count > 5 { textoCodigo = String(v.prefix(5)) }
                        }
                    TextField("PIN".localized(), text: $textoPIN)
                        .keyboardType(.numberPad)
                        .onChange(of: textoPIN) { v in
                            if v.count > 4 { textoPIN = String(v.prefix(4)) }
                        }
                }
            }
            .navigationTitle("Conectar a otra aula".localized())
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Diálogo Etiquetar aula

struct DialogoEtiqueta: View {
    @Binding var textoEtiqueta: String
    let onGuardar: (String) -> Void
    let onCancelar: () -> Void

    var puedeGuardar: Bool {
        textoEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Etiqueta".localized(), text: $textoEtiqueta)
                        .autocapitalization(.sentences)
                        .keyboardType(.asciiCapable)
                        .onChange(of: textoEtiqueta) { v in
                            if v.count > 50 { textoEtiqueta = String(v.prefix(50)) }
                        }
                }
            }
            .navigationTitle("Etiquetar aula".localized())
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Diálogo Tiempo de espera

struct DialogoTiempoEspera: View {
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
            Picker("Tiempo de espera (minutos)".localized(), selection: $seleccion) {
                ForEach(tiempos, id: \.self) { t in
                    Text("\(t)").tag(t)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle("Tiempo de espera (minutos)".localized())
            .navigationBarTitleDisplayMode(.inline)
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
        guard vm.codigoAula != "?" else { return "No hay conexión de red".localized() }
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
            .padding(.vertical, 16)
            .padding(.horizontal, 20)

            Divider()

            // Acciones
            List {
                if !vm.invitado, vm.codigoAula != "?" {
                    Button {
                        onCerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onEtiquetar() }
                    } label: {
                        Label(
                            vm.etiquetaAula.count > 0
                                ? String(format: "» %@ «", vm.etiquetaAula)
                                : "Etiquetar aula".localized(),
                            systemImage: "tag"
                        )
                    }

                    Button {
                        onCerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onTiempo() }
                    } label: {
                        Label("Establecer tiempo de espera".localized(), systemImage: "timer")
                    }

                    if vm.numAulas < vm.MAX_AULAS {
                        Button {
                            onCerrar(); vm.anyadirAula()
                        } label: {
                            Label("Añadir aula".localized(), systemImage: "plus.circle")
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
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Button {
                        onCerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onConectar() }
                    } label: {
                        Label("Conectar a otra aula".localized(), systemImage: "arrow.triangle.2.circlepath")
                    }
                } else if vm.invitado {
                    Button(role: .destructive) {
                        onCerrar(); vm.desconectarAula()
                    } label: {
                        Label("Desconectar del aula".localized(), systemImage: "xmark.circle")
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
                    Image("Fondo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: tamanyoCirculoPrincipal * 0.85,
                               height: tamanyoCirculoPrincipal * 0.85)
                        .opacity(0.025)

                    Text(vm.nombreAlumno)
                        .font(.system(size: 51))
                        .minimumScaleFactor(0.2)
                        .lineLimit(1)
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: tamanyoCirculoPrincipal - 32)
                }
                .frame(width: tamanyoCirculoPrincipal, height: tamanyoCirculoPrincipal)
                .background(Circle().fill(Color(red: 0.996, green: 0.773, blue: 0.180)))
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
                    colorFondo: Color(red: 0.875, green: 0.886, blue: 0.902),
                    colorTexto: .black,
                    tamanyo: tamanyoBoton,
                    fuente: .system(size: 15, weight: .regular)
                ) {
                    vm.feedbackTactilLigero()
                    onMostrarMenu()
                }
                .position(posicionEnBorde(angulo: -60, centroX: centroX, centroY: centroY, radio: radio))
                .accessibilityIdentifier("botonCodigoAula")

                // Botón número en cola (rojo, 30°)
                BotónCircular(
                    titulo: "\(vm.enCola)",
                    colorFondo: Color(red: 0.925, green: 0.263, blue: 0.220),
                    colorTexto: .white,
                    tamanyo: tamanyoBoton
                ) {
                    vm.simularBotonEnCola()
                }
                .position(posicionEnBorde(angulo: 30, centroX: centroX, centroY: centroY, radio: radio))
                .accessibilityIdentifier("botonEnCola")

                // Botón siguiente (azul, 150°)
                BotónCircularIcono(
                    simbolo: "arrow.right",
                    colorFondo: Color(red: 0.063, green: 0.463, blue: 0.725),
                    colorIcono: .white,
                    tamanyo: tamanyoBoton
                ) {
                    vm.feedbackTactilLigero()
                    vm.mostrarSiguiente(avanzarCola: true)
                }
                .opacity(opacidadBotonSiguiente)
                ._onButtonGesture(pressing: { pressing in
                    withAnimation(.linear(duration: pressing ? 0.1 : 0.3)) {
                        opacidadBotonSiguiente = pressing ? 0.15 : 1.0
                    }
                }, perform: {})
                .position(posicionEnBorde(angulo: 150, centroX: centroX, centroY: centroY, radio: radio))
                .accessibilityIdentifier("botonSiguiente")

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

// MARK: - Preview

#Preview {
    ContentView()
}
