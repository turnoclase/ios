//
//  Colores.swift
//  TurnoClaseShared
//
//  Created by Ion Jaureguialzo Sarasola on 24/03/2026.
//  Copyright © 2026 Ion Jaureguialzo Sarasola. All rights reserved.
//

// Source - https://stackoverflow.com/a/69944861
// Posted by P. Ent
// Retrieved 2026-03-24, License - CC BY-SA 4.0

import SwiftUI

private class LocalColor {
    // only to provide a Bundle reference
}

public extension Color {
    static var azul: Color {
        Color("Azul", bundle: Bundle(for: LocalColor.self))
    }

    static var rojo: Color {
        Color("Rojo", bundle: Bundle(for: LocalColor.self))
    }

    static var amarillo: Color {
        Color("Amarillo", bundle: Bundle(for: LocalColor.self))
    }

    static var gris: Color {
        Color("Gris", bundle: Bundle(for: LocalColor.self))
    }
}
