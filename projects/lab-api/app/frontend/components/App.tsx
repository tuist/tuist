/** @jsx jsx */
import React from "react";
import ErrorTracking from "./ErrorTracking";
import { ThemeProvider, jsx } from "theme-ui";
import theme from "../style/theme";

const App = () => {
  // @ts-ignore
  return (
    <ErrorTracking>
      <ThemeProvider theme={theme}>
        <div sx={{ bg: "red" }}>Hello it xxxxasdgas;</div>
      </ThemeProvider>
    </ErrorTracking>
  );
};

export default App;
