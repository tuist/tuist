---
name: Graph
---

# Graph

When projects grow, it becomes hard to visualize the dependencies between all the targets that are part of the project. Fortunately, Tuist provides a command, `tuist graph`, that loads your project dependencies graph and exports it in a representable format.

Being in a directory that contains a workspace or project manifest, run the following command:

```bash
tuist graph
```

The command will output a human-readable file, `graph.dot` that describes the dependencies graph using the [DOT](<https://en.wikipedia.org/wiki/DOT_(graph_description_language)>) description language.

## A visual representation of the graph

[Graphviz](https://formulae.brew.sh/formula/graphviz) is a command line tool that take the `.dot` graph and convert it into an image.

```bash
brew install graphviz
dot -Tpng graph.dot > graph.png
```

Alternatively, you can use online services like [this one](https://dreampuf.github.io/GraphvizOnline) that renders your graph on a website.
