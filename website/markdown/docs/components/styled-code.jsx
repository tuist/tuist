/** @jsx jsx */
import { jsx } from "theme-ui";

export default ({children}) => {
  return <code sx={{
    fontFamily: 'Menlo, Consolas, Monaco, "Courier New", monospace, serif',
    fontSize: "13px",
    color: "rgb(125, 137, 156)"
  }}>{children}</code>
}
