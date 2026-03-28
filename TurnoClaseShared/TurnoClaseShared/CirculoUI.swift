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
// CirculoUI.swift
// TurnoClaseShared
//
// Componentes SwiftUI reutilizables entre TurnoClase y TurnoClaseProfesor.

import SwiftUI

// MARK: - Imágenes del bundle de TurnoClaseShared

private class BundleToken {}

public extension Image {
    static let flecha   = Image("Flecha",   bundle: Bundle(for: BundleToken.self))
    static let equis    = Image("Equis",    bundle: Bundle(for: BundleToken.self))
    static let recargar = Image("Recargar", bundle: Bundle(for: BundleToken.self))
    static let persona  = Image("Persona",  bundle: Bundle(for: BundleToken.self))
}

// MARK: - Utilidad: modificador condicional

public extension View {
    /// Permite aplicar un bloque de modificadores de forma condicional o según disponibilidad.
    func modify<T: View>(@ViewBuilder _ transform: (Self) -> T) -> some View {
        transform(self)
    }
}

// MARK: - Posicionamiento sobre el borde de un círculo

/// Calcula el punto central de un elemento situado sobre el borde de un círculo.
/// - Parameters:
///   - angulo: Ángulo en grados. 0° = parte superior, sentido horario.
///   - centroX: Coordenada X del centro del círculo.
///   - centroY: Coordenada Y del centro del círculo.
///   - radio: Radio del círculo.
/// - Returns: CGPoint con la posición resultante.
public func posicionEnBorde(angulo: Double, centroX: CGFloat, centroY: CGFloat, radio: CGFloat) -> CGPoint {
    let rad = (angulo - 90) * .pi / 180
    return CGPoint(
        x: centroX + radio * CGFloat(cos(rad)),
        y: centroY + radio * CGFloat(sin(rad))
    )
}

// MARK: - Botón circular genérico

/// Botón con forma circular, título centrado y fondo de color sólido.
public struct BotónCircular: View {
    public let titulo: String
    public let colorFondo: Color
    public let colorTexto: Color
    public let tamanyo: CGFloat
    public var fuente: Font
    public let accion: () -> Void

    public init(
        titulo: String,
        colorFondo: Color,
        colorTexto: Color,
        tamanyo: CGFloat,
        fuente: Font = .system(size: 17, weight: .regular),
        accion: @escaping () -> Void
    ) {
        self.titulo = titulo
        self.colorFondo = colorFondo
        self.colorTexto = colorTexto
        self.tamanyo = tamanyo
        self.fuente = fuente
        self.accion = accion
    }

    @State private var pulsado = false

    public var body: some View {
        Circle()
            .fill(colorFondo)
            .frame(width: tamanyo, height: tamanyo)
            .overlay(
                Text(titulo)
                    .font(fuente)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .foregroundColor(colorTexto)
                    .opacity(pulsado ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: pulsado)
            )
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pulsado = true }
                    .onEnded { _ in
                        pulsado = false
                        accion()
                    }
            )
    }
}

// MARK: - Botón circular con símbolo SF o asset personalizado

/// Botón circular que muestra una imagen (SF Symbol o asset del catálogo) en lugar de texto.
public struct BotónCircularIcono: View {
    public let imagen: Image
    public let colorFondo: Color
    public let colorIcono: Color
    public let tamanyo: CGFloat
    public let tamanyoFuente: CGFloat
    public let accion: () -> Void

    public init(
        imagen: Image,
        colorFondo: Color,
        colorIcono: Color,
        tamanyo: CGFloat,
        tamanyoFuente: CGFloat = 42,
        accion: @escaping () -> Void
    ) {
        self.imagen = imagen
        self.colorFondo = colorFondo
        self.colorIcono = colorIcono
        self.tamanyo = tamanyo
        self.tamanyoFuente = tamanyoFuente
        self.accion = accion
    }

    @State private var pulsado = false

    public var body: some View {
        Circle()
            .fill(colorFondo)
            .frame(width: tamanyo, height: tamanyo)
            .overlay(
                imagen
                    .font(.system(size: tamanyoFuente, weight: .medium))
                    .foregroundColor(colorIcono)
                    .opacity(pulsado ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: pulsado)
            )
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pulsado = true }
                    .onEnded { _ in
                        pulsado = false
                        accion()
                    }
            )
    }
}

// MARK: - Animación de tres puntos en onda

/// Tres puntos que suben y bajan en onda, para indicar estado de espera/carga.
///
/// La duración mínima de visibilidad se controla desde el ViewModel mediante
/// `terminarCarga()`, que retarda la asignación de `cargando = false`.
public struct AnimacionPuntos: View {
    public let color: Color
    public let tamanyo: CGFloat

    public init(color: Color = .black, tamanyo: CGFloat = 14) {
        self.color = color
        self.tamanyo = tamanyo
    }

    @State private var animar = false

    private let delays: [Double] = [0, 0.18, 0.36]

    public var body: some View {
        HStack(spacing: tamanyo * 0.8) {
            ForEach(0 ..< 3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: tamanyo, height: tamanyo)
                    .offset(y: animar ? -tamanyo * 0.9 : tamanyo * 0.9)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(delays[i]),
                        value: animar
                    )
            }
        }
        .onAppear { animar = true }
        .onDisappear { animar = false }
    }
}

// MARK: - PageControl SwiftUI wrapper

/// Wrapper de UIPageControl para usar en SwiftUI.
public struct PageControlView: UIViewRepresentable {
    public let currentPage: Int
    public let totalPages: Int

    public init(currentPage: Int, totalPages: Int) {
        self.currentPage = currentPage
        self.totalPages = totalPages
    }

    public func makeUIView(context: Context) -> UIPageControl {
        let pc = UIPageControl()
        pc.hidesForSinglePage = true
        pc.isUserInteractionEnabled = false
        pc.pageIndicatorTintColor = UIColor.tertiaryLabel
        pc.currentPageIndicatorTintColor = UIColor.secondaryLabel
        return pc
    }

    public func updateUIView(_ uiView: UIPageControl, context: Context) {
        uiView.numberOfPages = totalPages
        uiView.currentPage = currentPage
    }
}
