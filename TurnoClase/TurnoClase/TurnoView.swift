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
// TurnoView.swift
// TurnoClase
//
// Pantalla de turno: muestra el estado en la cola y permite cancelar o actualizar.

import SwiftUI
import TurnoClaseShared

struct TurnoView: View {
    @ObservedObject var vm: ConexionViewModel
    @State private var opacidadBotonActualizar: Double = 1.0

    var body: some View {
        GeometryReader { geo in
            let tamanyoCirculo: CGFloat = min(geo.size.width, geo.size.height) * 0.70
            let tamanyoBoton: CGFloat = 72
            let centroX = geo.size.width / 2 + 8
            let centroY = geo.size.height / 2 - 12
            let radio = tamanyoCirculo / 2

            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                // Círculo gris principal
                ZStack {
                    // Imagen de fondo tenue
                    Image("Fondo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: tamanyoCirculo * 0.85,
                               height: tamanyoCirculo * 0.85)
                        .opacity(0.04)

                    // Contenido central
                    Group {
                        if vm.mostrarCronometro {
                            // Cronómetro
                            VStack(spacing: 4) {
                                Text(NSLocalizedString("ESPERA", comment: ""))
                                    .font(.system(size: 20))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.black)
                                Text(String(format: "%02d:%02d", vm.minutosRestantes, vm.segundosRestantes))
                                    .font(.system(size: 48, weight: .thin, design: .monospaced))
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 20)
                        } else if vm.mostrarError {
                            // Error
                            Text(NSLocalizedString("MENSAJE_ERROR", comment: ""))
                                .font(.system(size: 22))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.black)
                                .padding(.horizontal, 20)
                        } else {
                            // Mensaje de estado
                            Text(mensajeEstado)
                                .font(.system(size: mensajeFontSize))
                                .minimumScaleFactor(0.3)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.black)
                                .padding(.horizontal, 20)
                                .frame(maxWidth: tamanyoCirculo - 32)
                        }
                    }
                }
                .frame(width: tamanyoCirculo, height: tamanyoCirculo)
                .background(Circle().foregroundColor(.gris))
                .position(x: centroX, y: centroY)

                // Botón código de aula (amarillo, 30°)
                BotónCircular(
                    titulo: vm.codigoAulaActual,
                    colorFondo: .amarillo,
                    colorTexto: .black,
                    tamanyo: tamanyoBoton,
                ) {}
                    .position(posicionEnBorde(angulo: 30, centroX: centroX, centroY: centroY, radio: radio))
                    .accessibilityIdentifier("botonCodigoAula")

                // Botón cancelar (rojo, -60°)
                BotónCircularIcono(
                    simbolo: "xmark",
                    colorFondo: .rojo,
                    colorIcono: .white,
                    tamanyo: tamanyoBoton
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    vm.cancelar()
                }
                .position(posicionEnBorde(angulo: -60, centroX: centroX, centroY: centroY, radio: radio))
                .accessibilityIdentifier("botonCancelar")

                // Botón actualizar (azul, 150°)
                BotónCircularIcono(
                    simbolo: "arrow.clockwise",
                    colorFondo: .azul,
                    colorIcono: .white,
                    tamanyo: tamanyoBoton
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    vm.actualizar()
                }
                .opacity(opacidadBotonActualizar)
                ._onButtonGesture(pressing: { pressing in
                    withAnimation(.linear(duration: pressing ? 0.1 : 0.3)) {
                        opacidadBotonActualizar = pressing ? 0.15 : 1.0
                    }
                }, perform: {})
                .opacity(vm.mostrarBotonActualizar ? 1.0 : 0.0)
                .disabled(!vm.mostrarBotonActualizar)
                .position(posicionEnBorde(angulo: 150, centroX: centroX, centroY: centroY, radio: radio))
                .accessibilityIdentifier("botonActualizar")
            }
        }
    }

    // MARK: - Helpers

    private var mensajeEstado: String {
        switch vm.estadoTurno {
        case .enCola(let pos):
            return "\(pos)"
        case .esTuTurno:
            return NSLocalizedString("ES_TU_TURNO", comment: "")
        case .volverAEmpezar:
            return NSLocalizedString("VOLVER_A_EMPEZAR", comment: "")
        case .esperando:
            return NSLocalizedString("ESPERA", comment: "")
        case .error(let msg):
            return msg
        }
    }

    private var mensajeFontSize: CGFloat {
        switch vm.estadoTurno {
        case .enCola:
            return 72
        default:
            return 30
        }
    }
}

#Preview {
    TurnoView(vm: ConexionViewModel())
}
