/** @jsx jsx */
import { jsx, Styled } from "theme-ui";

import { withPrefix } from "gatsby";
import StyledHeader from "./styled-header";

const HomeHeader = ({ gettingStartedUrl }) => {
  return (
    <StyledHeader p={[4, 4]} pb={[3, 3]}>
      <div
        sx={{
          display: "flex",
          flex: 1,
          flexDirection: "column",
          alignItems: "center"
        }}
      >
        <img
          src={withPrefix("logo.svg")}
          sx={{ height: [60, 100], width: [60, 100] }}
        />
        <Styled.h1
          sx={{
            p: [2, 2],
            flex: 1,
            color: "primaryComplementary",
            display: "flex",
            marginBottom: 1
          }}
        >
          Tuist
        </Styled.h1>

        <div
          sx={{
            flex: 1,
            width: ["70%", "90%"],
            color: "primaryComplementary",
            textAlign: "center"
          }}
        >
          Bootstrap, maintain, and interact with Xcode projects at any scale
        </div>

        <div
          sx={{
            display: "flex",
            p: 3,
            flexWrap: "wrap",
            justifyContent: "center"
          }}
        >
          <a
            href={gettingStartedUrl}
            target="__blank"
            sx={{
              borderRadius: 2,
              color: "primary",
              p: 3,
              bg: "primaryComplementary",
              "&:hover": {
                textDecoration: "none",
                bg: "primary",
                color: "primaryComplementary",
                boxShadow: theme =>
                  `0px 0px 0px 1px ${theme.colors.primaryComplementary} inset`
              }
            }}
          >
            Getting started
          </a>
        </div>
      </div>
    </StyledHeader>
  );
};

export default HomeHeader;
