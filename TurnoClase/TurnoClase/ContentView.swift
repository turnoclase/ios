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
// TurnoClase
//
// Pantalla inicial: introduce el código de aula y el nombre.

import SwiftUI
import TurnoClaseShared

struct ContentView: View {
    @StateObject private var vm = ConexionViewModel()
    @FocusState private var campoActivo: Campo?

    enum Campo { case aula, nombre }

    var body: some View {
        Group {
            if vm.mostrandoTurno {
                TurnoView(vm: vm)
            } else {
                pantallaInicial
            }
        }
        .onAppear { vm.iniciar() }
    }

    // MARK: - Pantalla inicial

    private var pantallaInicial: some View {
        GeometryReader { geo in
            let tamanyoCirculo: CGFloat = min(geo.size.width, geo.size.height) * 0.70
            let tamanyoBoton: CGFloat = 72
            let centroX = geo.size.width / 2 + 8
            let centroY = geo.size.height / 2 - 12

            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                // Círculo gris principal
                ZStack {
                    // Símbolo de fondo tenue
                    Image.persona
                        .resizable()
                        .scaledToFit()
                        .frame(width: tamanyoCirculo * 0.60,
                               height: tamanyoCirculo * 0.60)
                        .foregroundColor(.black)
                        .opacity(0.025)

                    // Campos de texto
                    VStack(spacing: 3) {
                        Text("AULA")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.black)
                            .kerning(1)

                        TextField("BE131", text: $vm.codigoAula)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(.black)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 100)
                                    .fill(Color.white)
                            )
                            .autocapitalization(.allCharacters)
                            .autocorrectionDisabled(true)
                            .keyboardType(.asciiCapable)
                            .submitLabel(.next)
                            .focused($campoActivo, equals: .aula)
                            .onChange(of: vm.codigoAula) { v in
                                if v.count > 5 { vm.codigoAula = String(v.prefix(5)) }
                                vm.codigoAula = v.uppercased()
                            }
                            .onSubmit { campoActivo = .nombre }

                        Text("NOMBRE")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.black)
                            .kerning(1)
                            .padding(.top, 12)

                        TextField(vm.placeholder, text: $vm.nombreUsuario)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(.black)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 100)
                                    .fill(Color.white)
                            )
                            .autocapitalization(.words)
                            .submitLabel(.go)
                            .focused($campoActivo, equals: .nombre)
                            .onChange(of: vm.nombreUsuario) { v in
                                if v.count > 15 { vm.nombreUsuario = String(v.prefix(15)) }
                            }
                            .onSubmit {
                                campoActivo = nil
                                if vm.puedeConectar { vm.conectar() }
                            }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .frame(maxWidth: tamanyoCirculo - 16)
                }
                .frame(width: tamanyoCirculo, height: tamanyoCirculo)
                .background(Circle().foregroundColor(.gris))
                .position(x: centroX, y: centroY)
                .onTapGesture { campoActivo = nil }

                // Botón siguiente (azul, sobre el borde a 150°)
                BotónCircularIcono(
                    imagen: .flecha,
                    colorFondo: .azul,
                    colorIcono: .white,
                    tamanyo: tamanyoBoton
                ) {
                    campoActivo = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    vm.conectar()
                }
                .disabled(!vm.puedeConectar)
                .opacity(vm.puedeConectar ? 1.0 : 0.4)
                .position(posicionEnBorde(angulo: 150, centroX: centroX, centroY: centroY, radio: tamanyoCirculo / 2))
            }
        }
    }
}

#Preview {
    ContentView()
}
