/** @jsx jsx */
import { jsx } from "theme-ui";

import StyledHeader from "./styled-header";
import { Styled } from "theme-ui";

const TitledHeader = ({ title, subtitle, children }) => {
  const sx = {
    width: theme => ["90%", "90%", "80%", "80%", theme.breakpoints.md]
  };
  return (
    <StyledHeader>
      {children && (
        <div
          sx={{
            display: "flex",
            mt: [3, 0],
            mb: [3, 3],
            flexDirection: "column",
            alignItems: "center"
          }}
        >
          {children}
        </div>
      )}

      <div sx={sx}>
        <Styled.h1 sx={{ color: "white", textAlign: "center" }}>
          {title}
        </Styled.h1>
      </div>

      {subtitle && (
        <div
          sx={{
            ...sx,
            flex: 1,
            color: "white",
            fontSize: [2, 3],
            textAlign: "center"
          }}
        >
          {subtitle}
        </div>
      )}
    </StyledHeader>
  );
};

export default TitledHeader;
