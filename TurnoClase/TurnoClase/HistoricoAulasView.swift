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
// HistoricoAulasView.swift
// TurnoClase
//
// Vista que muestra el histórico de aulas visitadas por el alumno.

import SwiftUI
import TurnoClaseShared

// MARK: - Envoltura que selecciona la versión adecuada

struct HistoricoAulasView: View {
    @Binding var historico: [AulaHistorico]
    let onSeleccionar: (AulaHistorico) -> Void
    let onCerrar: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            HistoricoAulasView26(
                historico: $historico,
                onSeleccionar: onSeleccionar,
                onCerrar: onCerrar
            )
        } else {
            HistoricoAulasViewLegacy(
                historico: $historico,
                onSeleccionar: onSeleccionar,
                onCerrar: onCerrar
            )
        }
    }
}

// MARK: - Versión legacy (iOS < 26)

private struct HistoricoAulasViewLegacy: View {
    @Binding var historico: [AulaHistorico]
    let onSeleccionar: (AulaHistorico) -> Void
    let onCerrar: () -> Void

    @State private var aulaParaEtiquetar: AulaHistorico? = nil
    @State private var mostrandoAlerta: Bool = false
    @State private var textoEtiqueta: String = ""
    @State private var modoEdicion: EditMode = .inactive

    var body: some View {
        NavigationView {
            Group {
                if historico.isEmpty {
                    contenidoVacio
                } else {
                    listaAulas
                }
            }
            .navigationTitle(NSLocalizedString("HISTORICO_TITULO", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("CERRAR", comment: "")) { onCerrar() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !historico.isEmpty {
                        Button(modoEdicion == .active
                            ? NSLocalizedString("LISTO", comment: "")
                            : NSLocalizedString("EDITAR", comment: ""))
                        {
                            withAnimation { modoEdicion = modoEdicion == .active ? .inactive : .active }
                        }
                    }
                }
            }
        }
        .alert(NSLocalizedString("HISTORICO_ETIQUETA_TITULO", comment: ""), isPresented: $mostrandoAlerta) {
            TextField(NSLocalizedString("HISTORICO_ETIQUETA_PLACEHOLDER", comment: ""), text: $textoEtiqueta)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .onChange(of: textoEtiqueta) { nuevo in
                    if nuevo.count > 20 { textoEtiqueta = String(nuevo.prefix(20)) }
                }
            Button(NSLocalizedString("GUARDAR", comment: "")) {
                if let aula = aulaParaEtiquetar,
                   let index = historico.firstIndex(where: { $0.id == aula.id })
                {
                    historico[index].etiqueta = textoEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
                    HistoricoAulas.guardar(historico)
                }
            }
            Button(NSLocalizedString("CANCELAR", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("HISTORICO_ETIQUETA_MENSAJE", comment: ""))
        }
    }

    private var contenidoVacio: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("HISTORICO_VACIO", comment: ""))
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listaAulas: some View {
        List {
            ForEach($historico) { $aula in
                FilaAulaLegacy(
                    aula: aula,
                    onSeleccionar: {
                        onSeleccionar(aula)
                        onCerrar()
                    },
                    onEtiquetar: {
                        aulaParaEtiquetar = aula
                        textoEtiqueta = aula.etiqueta
                        mostrandoAlerta = true
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        eliminar(aula)
                    } label: {
                        Label(NSLocalizedString("ELIMINAR", comment: ""), systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets {
                    eliminar(historico[i])
                }
            }
            .onMove { source, destination in
                historico.move(fromOffsets: source, toOffset: destination)
                HistoricoAulas.guardar(historico)
            }
        }
        .environment(\.editMode, $modoEdicion)
    }

    private func eliminar(_ aula: AulaHistorico) {
        historico.removeAll { $0.id == aula.id }
        HistoricoAulas.guardar(historico)
    }
}

// Fila que lee editMode directamente del entorno de la List
private struct FilaAulaLegacy: View {
    let aula: AulaHistorico
    let onSeleccionar: () -> Void
    let onEtiquetar: () -> Void

    @Environment(\.editMode) private var editMode

    var body: some View {
        HStack(spacing: 12) {
            Text(aula.codigo)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 72, height: 32)
                .background(Capsule().foregroundColor(.gris))
                .onTapGesture {
                    guard editMode?.wrappedValue == .inactive else { return }
                    onSeleccionar()
                }

            Group {
                if !aula.etiqueta.isEmpty {
                    Text(aula.etiqueta)
                        .font(.body)
                } else {
                    Text(NSLocalizedString("HISTORICO_SIN_ETIQUETA", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .onTapGesture {
                guard editMode?.wrappedValue == .inactive else { return }
                onEtiquetar()
            }

            Spacer()
        }
    }
}

// MARK: - Versión iOS 26

@available(iOS 26, *)
private struct HistoricoAulasView26: View {
    @Binding var historico: [AulaHistorico]
    let onSeleccionar: (AulaHistorico) -> Void
    let onCerrar: () -> Void

    @State private var aulaParaEtiquetar: AulaHistorico? = nil
    @State private var mostrandoAlerta: Bool = false
    @State private var textoEtiqueta: String = ""
    @State private var modoEdicion: EditMode = .inactive

    var body: some View {
        NavigationStack {
            Group {
                if historico.isEmpty {
                    contenidoVacio
                } else {
                    listaAulas
                }
            }
            .navigationTitle(NSLocalizedString("HISTORICO_TITULO", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCerrar) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !historico.isEmpty {
                        Button(modoEdicion == .active
                            ? NSLocalizedString("LISTO", comment: "")
                            : NSLocalizedString("EDITAR", comment: ""))
                        {
                            withAnimation { modoEdicion = modoEdicion == .active ? .inactive : .active }
                        }
                    }
                }
            }
        }
        .alert(NSLocalizedString("HISTORICO_ETIQUETA_TITULO", comment: ""), isPresented: $mostrandoAlerta) {
            TextField(NSLocalizedString("HISTORICO_ETIQUETA_PLACEHOLDER", comment: ""), text: $textoEtiqueta)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .onChange(of: textoEtiqueta) { nuevo in
                    if nuevo.count > 20 { textoEtiqueta = String(nuevo.prefix(20)) }
                }
            Button(NSLocalizedString("GUARDAR", comment: "")) {
                if let aula = aulaParaEtiquetar,
                   let index = historico.firstIndex(where: { $0.id == aula.id })
                {
                    historico[index].etiqueta = textoEtiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
                    HistoricoAulas.guardar(historico)
                }
            }
            Button(NSLocalizedString("CANCELAR", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("HISTORICO_ETIQUETA_MENSAJE", comment: ""))
        }
    }

    private var contenidoVacio: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("HISTORICO_VACIO", comment: ""))
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listaAulas: some View {
        List {
            ForEach($historico) { $aula in
                FilaAula26(
                    aula: aula,
                    onSeleccionar: {
                        onSeleccionar(aula)
                        onCerrar()
                    },
                    onEtiquetar: {
                        aulaParaEtiquetar = aula
                        textoEtiqueta = aula.etiqueta
                        mostrandoAlerta = true
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        eliminar(aula)
                    } label: {
                        Label(NSLocalizedString("ELIMINAR", comment: ""), systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets {
                    eliminar(historico[i])
                }
            }
            .onMove { source, destination in
                historico.move(fromOffsets: source, toOffset: destination)
                HistoricoAulas.guardar(historico)
            }
        }
        .environment(\.editMode, $modoEdicion)
    }

    private func eliminar(_ aula: AulaHistorico) {
        historico.removeAll { $0.id == aula.id }
        HistoricoAulas.guardar(historico)
    }
}

@available(iOS 26, *)
private struct FilaAula26: View {
    let aula: AulaHistorico
    let onSeleccionar: () -> Void
    let onEtiquetar: () -> Void

    @Environment(\.editMode) private var editMode

    var body: some View {
        HStack(spacing: 12) {
            Text(aula.codigo)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 72, height: 32)
                .background(Capsule().foregroundColor(.gris))
                .onTapGesture {
                    guard editMode?.wrappedValue == .inactive else { return }
                    onSeleccionar()
                }

            Group {
                if !aula.etiqueta.isEmpty {
                    Text(aula.etiqueta)
                        .font(.body)
                } else {
                    Text(NSLocalizedString("HISTORICO_SIN_ETIQUETA", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .onTapGesture {
                guard editMode?.wrappedValue == .inactive else { return }
                onEtiquetar()
            }

            Spacer()
        }
    }
}
