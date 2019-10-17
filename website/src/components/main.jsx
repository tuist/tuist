/** @jsx jsx */
import { jsx } from "theme-ui";

const Main = ({ background, children }) => {
  return (
    <main
      sx={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        bg: ["background", "primary"]
      }}
    >
      <div
        sx={{
          bg: "background",
          mt: 3,
          px: [2, 5],
          borderTopLeftRadius: 2,
          borderTopRightRadius: 2,
          width: theme => ["90%", "90%", "80%", "80%", theme.breakpoints.md]
        }}
      >
        {children}
      </div>
    </main>
  );
};

export default Main;
