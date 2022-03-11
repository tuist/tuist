import React from 'react';

interface LinkButtonProps {
  href: string;
  method?: 'post' | 'get';
  children: JSX.Element | string;
}

const LinkButton = ({ href, children, method }: LinkButtonProps) => {
  return (
    <a
      className="Polaris-Button"
      href={href}
      data-polaris-unstyled="true"
      data-method={method ?? 'get'}
    >
      <span className="Polaris-Button__Content">
        <span className="Polaris-Button__Text">{children}</span>
      </span>
    </a>
  );
};

export default LinkButton;
