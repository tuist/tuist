/** @jsx jsx */
import { jsx } from "theme-ui";

export default ({  children }) => {
  return (
    <main
      sx={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
      }}
    >
      <div
        sx={{
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