---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# Importy domyślne {#implicit-imports}

Aby zmniejszyć złożoność utrzymywania grafu projektu Xcode w przypadku surowego
projektu Xcode, firma Apple zaprojektowała system kompilacji w sposób
umożliwiający domyślne definiowanie zależności. Oznacza to, że produkt, na
przykład aplikacja, może zależeć od frameworka, nawet bez jawnego deklarowania
tej zależności. Na małą skalę jest to w porządku, ale wraz ze wzrostem
złożoności grafu projektu domyślność ta może przejawiać się w postaci zawodnych
kompilacji przyrostowych lub funkcji opartych na edytorze, takich jak podgląd
lub autouzupełnianie kodu.

Problem polega na tym, że nie da się zapobiec powstawaniu zależności domyślnych.
Każdy programista może dodać do swojego kodu Swift instrukcję import `` , co
spowoduje utworzenie zależności domyślnej. W tym miejscu z pomocą przychodzi
Tuist. Tuist udostępnia polecenie umożliwiające sprawdzenie zależności
domyślnych poprzez statyczną analizę kodu w projekcie. Poniższe polecenie
wyświetli zależności domyślne projektu:

```bash
tuist inspect dependencies --only implicit
```

Jeśli polecenie wykryje jakiekolwiek domyślne importy, zakończy działanie z
kodem wyjścia innym niż zero.

::: tip VALIDATE IN CI
<!-- -->
Zdecydowanie zalecamy uruchamianie tego polecenia w ramach
<LocalizedLink href="/guides/features/automate/continuous-integration">ciągłej
integracji</LocalizedLink> za każdym razem, gdy nowy kod jest przesyłany do
upstreamu.
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Ponieważ Tuist opiera się na statycznej analizie kodu w celu wykrywania ukrytych
zależności, może nie wychwycić wszystkich przypadków. Na przykład Tuist nie jest
w stanie zrozumieć importów warunkowych realizowanych za pomocą dyrektyw
kompilatora w kodzie.
<!-- -->
:::
