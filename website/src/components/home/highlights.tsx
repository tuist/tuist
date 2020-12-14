import React from 'react'

const Highlight = ({ title, description }) => {
  return (
    <article>
      <header>{title}</header>
      <div>{description}</div>
    </article>
  )
}

const Highlights = () => {
  return (
    <div className="max-w-70 mx-auto flex flex-row">
      <Highlight
        title="Swift manifest"
        description="Define projects using a simple Swift DSL inside Xcode"
      />
      <Highlight
        title="Project description helpers"
        description="Create your own abstrations to make your projects consistent"
      />
      <Highlight
        title="Scaffold"
        description="Automate feature creation by generating a target pre-configured with everything you need"
      />
    </div>
  )
}

export default Highlights
