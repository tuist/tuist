import React from "react";
import Menu from "./menu";
import { ColorMode } from "theme-ui";
import "../styles/main.css";

const Layout = ({ children }) => {
  return (
    <>
      <ColorMode />
      <Menu />
      {children}
    </>
  );
};

export default Layout;
