/** @jsx jsx */
import { jsx } from "theme-ui";
import ToggleButton from "./toggle-button";

const StyledHeader = ({ children }) => {
  return (
    <div
      sx={{
        bg: "primary",
        py: [4, 4],
        color: "primaryComplementary",
        display: "flex",
        flexDirection: "column",
        alignItems: "center"
      }}
    >
      <div
        sx={{
          display: ["none", "none", "block"],
          position: "absolute",
          top: 4,
          right: [2, 4, 4]
        }}
      >
        <ToggleButton />
      </div>

      {children}
    </div>
  );
};

export default StyledHeader;
