---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# Importy domyślne {#implicit-imports}

Aby zmniejszyć złożoność utrzymywania wykresu projektu Xcode z surowym projektem
Xcode, firma Apple zaprojektowała system kompilacji w taki sposób, aby umożliwić
niejawne definiowanie zależności. Oznacza to, że produkt, na przykład aplikacja,
może być zależny od frameworka, nawet bez jawnego deklarowania tej zależności. W
małej skali nie stanowi to problemu, ale wraz ze wzrostem złożoności wykresu
projektu niejawność może przejawiać się w postaci zawodnych kompilacji
przyrostowych lub funkcji opartych na edytorze, takich jak podgląd lub
autouzupełnianie kodu.

Problem polega na tym, że nie można zapobiec powstawaniu ukrytych zależności.
Każdy programista może dodać do swojego kodu Swift instrukcję import` ` , co
spowoduje utworzenie ukrytej zależności. W tym miejscu z pomocą przychodzi
Tuist. Tuist udostępnia polecenie umożliwiające sprawdzenie ukrytych zależności
poprzez statyczną analizę kodu w projekcie. Poniższe polecenie wyświetli ukryte
zależności w projekcie:

```bash
tuist inspect dependencies --only implicit
```

Jeśli polecenie wykryje jakiekolwiek niejawne importy, zakończy działanie z
kodem wyjścia innym niż zero.

::: tip VALIDATE IN CI
<!-- -->
Zdecydowanie zalecamy uruchamianie tego polecenia jako części polecenia
<LocalizedLink href="/guides/features/automate/continuous-integration">ciągłej
integracji</LocalizedLink> za każdym razem, gdy nowy kod jest przesyłany do
upstreamu.
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Ponieważ Tuist opiera się na statycznej analizie kodu w celu wykrywania ukrytych
zależności, może nie wychwycić wszystkich przypadków. Na przykład Tuist nie jest
w stanie zrozumieć importów warunkowych poprzez dyrektywy kompilatora w kodzie.
<!-- -->
:::
