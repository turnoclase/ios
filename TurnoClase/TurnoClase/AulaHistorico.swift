// Copyright 2026 Ion Jaureguialzo Sarasola.
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
// AulaHistorico.swift
// TurnoClase
//
// Modelo de histórico de aulas visitadas por el alumno.

import Foundation

// MARK: - Modelo

struct AulaHistorico: Identifiable, Codable, Equatable {
    var id: UUID
    var codigo: String
    var etiqueta: String

    init(id: UUID = UUID(), codigo: String, etiqueta: String = "") {
        self.id = id
        self.codigo = codigo
        self.etiqueta = etiqueta
    }
}

// MARK: - Persistencia

enum HistoricoAulas {
    private static let clave = "historicoAulas"

    static func cargar() -> [AulaHistorico] {
        guard let data = UserDefaults.standard.data(forKey: clave),
              let lista = try? JSONDecoder().decode([AulaHistorico].self, from: data)
        else { return [] }
        return lista
    }

    static func guardar(_ lista: [AulaHistorico]) {
        if let data = try? JSONEncoder().encode(lista) {
            UserDefaults.standard.set(data, forKey: clave)
        }
    }

    /// Añade o actualiza el código en el histórico.
    /// Si el código ya existe, lo mueve al principio sin cambiar la etiqueta.
    /// Si no existe, lo inserta al principio con etiqueta vacía.
    @discardableResult
    static func registrarConexion(codigo: String) -> [AulaHistorico] {
        var lista = cargar()
        if let index = lista.firstIndex(where: { $0.codigo == codigo }) {
            // Mueve al principio manteniendo la etiqueta
            let existente = lista.remove(at: index)
            lista.insert(existente, at: 0)
        } else {
            lista.insert(AulaHistorico(codigo: codigo), at: 0)
        }
        guardar(lista)
        return lista
    }
}
