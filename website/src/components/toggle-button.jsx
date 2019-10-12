/** @jsx jsx */
import { jsx } from "theme-ui";
import { useColorMode } from "theme-ui";
import theme from "../gatsby-plugin-theme-ui";

const ToggleButton = ({ sx, ...props }) => {
  const [colorMode, setColorMode] = useColorMode();

  let colorModes = Object.keys(theme.colors.modes);
  colorModes.push("light");
  let nextColorMode = "light";
  const currentIndex = colorModes.indexOf(colorMode);
  if (currentIndex + 1 < colorModes.length) {
    nextColorMode = colorModes[currentIndex + 1];
  } else {
    nextColorMode = colorModes[0];
  }

  return (
    <div
      {...props}
      sx={{
        ...sx,
        color: "primaryComplementary",
        bg: "primary",
        cursor: "pointer",
        border: "solid",
        borderColor: "primaryComplementary",
        borderWidth: "1px",
        p: 2,
        borderRadius: 2
      }}
      onClick={e => {
        setColorMode(nextColorMode);
      }}
    >
      Toggle {nextColorMode.charAt(0).toUpperCase() + nextColorMode.slice(1)}
    </div>
  );
};

export default ToggleButton;
