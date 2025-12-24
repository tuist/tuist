---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# Import domyślny {#implicit-imports}

Aby złagodzić złożoność utrzymywania wykresu projektu Xcode z surowym projektem
Xcode, Apple zaprojektował system kompilacji w sposób, który umożliwia niejawne
definiowanie zależności. Oznacza to, że produkt, na przykład aplikacja, może
zależeć od frameworka, nawet bez jawnego deklarowania zależności. Na małą skalę
jest to w porządku, ale wraz ze wzrostem złożoności grafu projektu, niejawność
może objawiać się jako niewiarygodne przyrostowe kompilacje lub funkcje oparte
na edytorze, takie jak podglądy lub uzupełnianie kodu.

Problem polega na tym, że nie można zapobiec powstawaniu niejawnych zależności.
Każdy programista może dodać instrukcję `import` do swojego kodu Swift, a
niejawna zależność zostanie utworzona. Tutaj właśnie wkracza Tuist. Tuist
udostępnia polecenie do sprawdzania niejawnych zależności poprzez statyczną
analizę kodu w projekcie. Poniższe polecenie wyświetli niejawne zależności
projektu:

```bash
tuist inspect implicit-imports
```

Jeśli polecenie wykryje jakikolwiek niejawny import, zakończy działanie z kodem
wyjścia innym niż zero.

::: tip VALIDATE IN CI
<!-- -->
Zdecydowanie zalecamy uruchamianie tego polecenia jako części polecenia
<LocalizedLink href="/guides/features/automate/continuous-integration">ciągłej integracji</LocalizedLink> za każdym razem, gdy nowy kod jest przesyłany w górę
strumienia.
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Ponieważ Tuist opiera się na statycznej analizie kodu w celu wykrycia ukrytych
zależności, może nie wychwycić wszystkich przypadków. Na przykład, Tuist nie
jest w stanie zrozumieć importu warunkowego poprzez dyrektywy kompilatora w
kodzie.
<!-- -->
:::
