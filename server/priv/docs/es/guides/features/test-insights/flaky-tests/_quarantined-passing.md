### Por qué los tests en cuarentena pueden aparecer como aprobados {#quarantined-passing}

- Los **tests silenciados** siguen ejecutándose. Un test silenciado que falla se registra como **fallido** en la ejecución del caso de test y se marca como inestable; el estado por test no se sobrescribe. Lo que se sobrescribe es la **ejecución de tests completa**: si todos los casos de test que fallan en la ejecución están silenciados, la ejecución en su conjunto se informa como aprobada, de modo que los fallos silenciados no rompen la CI.
- Los **tests omitidos** no se ejecutan en absoluto, por lo que el panel sigue mostrando el estado de la última ejecución real del test. Esa instantánea puede tener semanas de antigüedad.
