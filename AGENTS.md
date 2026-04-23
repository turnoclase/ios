# AGENTS.md — TurnoClase iOS

## Descripción del repositorio

Aplicación iOS de TurnoClase, sistema de gestión de turnos de preguntas para el aula. El repositorio contiene tres proyectos Xcode organizados en un workspace compartido:

- **`TurnoClase/`** — App del alumno. Muestra el turno asignado y permite unirse a un aula introduciendo un código.
- **`TurnoClaseProfesor/`** — App del profesor. Gestiona el aula, asigna turnos y llama al backend para crear nuevas aulas.
- **`TurnoClaseShared/`** — Librería compartida (Swift Package o framework) con utilidades comunes: componentes UI (`CirculoUI`), colores, helper de Keychain, lista de nombres aleatorios y operadores opcionales.

El workspace raíz es `TurnoClase.xcworkspace`.

## Stack tecnológico

- **Lenguaje:** Swift
- **UI:** SwiftUI
- **Backend:** Firebase (Auth, Firestore, App Check, Cloud Functions)
- **Gestión de paquetes:** Swift Package Manager (resuelto en `TurnoClase.xcworkspace/xcshareddata/swiftpm/Package.resolved`)
- **Localización:** Inglés (`en`), Español (`es`), Euskera (`eu`)

## Estructura del repositorio

```
ios/
├── TurnoClase.xcworkspace/          # Workspace principal (abrir siempre éste)
├── TurnoClase/                      # App alumno
│   └── TurnoClase/
│       ├── TurnoClaseApp.swift      # Punto de entrada
│       ├── ContentView.swift        # Vista principal
│       ├── TurnoView.swift          # Vista del turno
│       ├── ConexionViewModel.swift  # ViewModel de conexión al aula
│       ├── HistoricoAulasView.swift # Vista del historial
│       └── AulaHistorico.swift      # Modelo del historial
├── TurnoClaseProfesor/              # App profesor
│   └── TurnoClaseProfesor/
│       ├── TurnoClaseProfesorApp.swift
│       ├── ContentView.swift
│       └── AulaViewModel.swift      # ViewModel del aula
└── TurnoClaseShared/                # Librería compartida
    └── TurnoClaseShared/
        ├── CirculoUI.swift          # Componente visual de círculo
        ├── Colores.swift            # Paleta de colores
        ├── KeychainHelper.swift     # Acceso al Keychain
        ├── Nombres.swift            # Generador de nombres aleatorios (es/en)
        └── OperadorOpcional.swift   # Operadores custom para opcionales
```

## Comandos habituales

Las builds se realizan desde Xcode o con `xcodebuild`. Abrir siempre el workspace, no los `.xcodeproj` individuales.

```bash
# Compilar la app del alumno (simulador)
xcodebuild -workspace TurnoClase.xcworkspace \
           -scheme TurnoClase \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           build

# Compilar la app del profesor (simulador)
xcodebuild -workspace TurnoClase.xcworkspace \
           -scheme TurnoClaseProfesor \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           build

# Ejecutar tests UI de la app del alumno
xcodebuild -workspace TurnoClase.xcworkspace \
           -scheme TurnoClase \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           test

# Generar strings de localización (desde TurnoClaseProfesor/)
swift genstrings.swift
```

## Convenciones

- El patrón arquitectural es MVVM: las vistas son SwiftUI (`*View.swift`), los ViewModels son clases `@Observable` o `ObservableObject` (`*ViewModel.swift`).
- El código compartido entre las dos apps debe ir en `TurnoClaseShared`.
- Las cadenas localizables van en `Localizable.strings` para cada idioma (`Base`, `es`, `eu`).
- Los recursos de Firebase (`GoogleService-Info.plist`) están incluidos en cada target y no deben regenerarse sin motivo.
- Los ficheros `.xcuserstate` y datos de usuario de Xcode están en `.gitignore`.

## Commits

Al completar cualquier característica o cambio, crear un commit con:

- **Mensaje en español**, en imperativo y conciso (p.ej. `Añadir vista de historial de aulas`).
- Un commit por característica o cambio cohesionado; no agrupar cambios no relacionados.
- No incluir ficheros de usuario de Xcode (`xcuserstate`, `xcuserdatad/`) ni carpetas `DerivedData/`.
- **Antes de hacer el commit**, verificar que el proyecto compila sin errores:

  ```bash
  xcodebuild -workspace TurnoClase.xcworkspace \
             -scheme TurnoClase \
             -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
             build
  ```

## Consideraciones para agentes

- Abrir siempre `TurnoClase.xcworkspace`, no los `.xcodeproj` individuales, para que las dependencias de SPM estén disponibles.
- Al modificar `TurnoClaseShared`, verificar la compatibilidad con los dos targets consumidores.
- No modificar `Package.resolved` manualmente; dejar que Xcode lo resuelva.
- El fichero `GoogleService-Info.plist` contiene configuración de Firebase; no incluir su contenido en logs ni en código.
- Las capturas de pantalla para el App Store se gestionan desde el repositorio `shared/`.
- Los ficheros de certificados y perfiles de aprovisionamiento residen en el repositorio `private/`.
