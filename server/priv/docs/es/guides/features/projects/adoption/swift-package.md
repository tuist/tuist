---
{
  "title": "Usar Tuist con un paquete Swift",
  "titleTemplate": ":title · Adopción · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar Tuist con un paquete Swift."
}
---
# Uso de Tuist con un paquete Swift <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist permite usar `Package.swift` como DSL para tus proyectos y convierte los destinos de tu paquete en un proyecto y unos destinos nativos de Xcode.

> [!WARNING]
> El objetivo de esta funcionalidad es ofrecer a las personas desarrolladoras una forma sencilla de evaluar el impacto de adoptar Tuist en sus paquetes Swift. Por ello, no planeamos admitir toda la gama de funcionalidades de Swift Package Manager ni llevar todas las funcionalidades exclusivas de Tuist, como <.localized_link href="/guides/features/projects/code-sharing">helpers de descripción de proyecto</.localized_link>, al ámbito de los paquetes.


> [!NOTE]
> **Directorio raíz**
>
> Los comandos de Tuist esperan una determinada <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">estructura de directorios</.localized_link> cuya raíz se identifica por un directorio `Tuist` o `.git` .


## Uso de Tuist con un paquete Swift {#using-tuist-with-a-swift-package}

Vamos a usar Tuist con el repositorio [TootSDK Package](https://github.com/TootSDK/TootSDK), que contiene un paquete Swift. Lo primero que debemos hacer es clonar el repositorio:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Una vez en el directorio del repositorio, debemos instalar las dependencias de Swift Package Manager:

```bash
tuist install
```

Internamente, `tuist install` usa Swift Package Manager para resolver y obtener las dependencias del paquete. Cuando finalice la resolución, puedes generar el proyecto:

```bash
tuist generate
```

¡Listo! Ya tienes un proyecto nativo de Xcode que puedes abrir y empezar a usar.
