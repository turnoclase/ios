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
// KeychainHelper.swift
// TurnoClaseShared

import Foundation
import Security

/// Acceso silencioso al Keychain del dispositivo.
///
/// Usa `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` para que:
/// - El ítem sobreviva a reinstalaciones de la app.
/// - No se transfiera a otros dispositivos ni aparezca en backups.
/// - Sea accesible en background tras el primer desbloqueo.
public struct KeychainHelper {

    private static let servicio: String = {
        // Usa el bundle identifier base sin el sufijo del target para que
        // ambas apps del mismo desarrollador puedan compartir ítems si
        // se configura un Keychain Access Group. Actualmente cada app
        // tiene su propio namespace al no compartir grupo explícito.
        Bundle.main.bundleIdentifier ?? "com.turnoclase"
    }()

    // MARK: - API pública

    /// Guarda o sobreescribe un valor de texto en el Keychain.
    @discardableResult
    public static func guardar(_ valor: String, clave: String) -> Bool {
        guard let data = valor.data(using: .utf8) else { return false }

        let busqueda: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
        ]

        // Intentar actualizar si el ítem ya existe
        let actualizar: [String: Any] = [
            kSecValueData as String: data,
            // Reafirmar la accesibilidad al actualizar
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let statusActualizar = SecItemUpdate(busqueda as CFDictionary, actualizar as CFDictionary)

        if statusActualizar == errSecSuccess {
            return true
        }

        if statusActualizar == errSecItemNotFound {
            // No existía: crear nuevo ítem
            var nuevoItem = busqueda
            nuevoItem[kSecValueData as String] = data
            nuevoItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let statusCrear = SecItemAdd(nuevoItem as CFDictionary, nil)
            return statusCrear == errSecSuccess
        }

        return false
    }

    /// Lee un valor de texto del Keychain. Devuelve `nil` si no existe.
    public static func leer(clave: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var resultado: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &resultado)

        guard status == errSecSuccess,
              let data = resultado as? Data,
              let valor = String(data: data, encoding: .utf8)
        else { return nil }

        return valor
    }

    /// Elimina un ítem del Keychain.
    @discardableResult
    public static func borrar(clave: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
