export const nil: "";
export const pointerSegments: (pointer: string) => Generator<string>;
export const append: (
    (segment: string, pointer: string) => string
  ) & (
    (segment: string) => (pointer: string) => string
  );
export const get: (
    (pointer: string, subject: Pointable) => unknown
  ) & (
    (pointer: string) => Getter
  );
export const set: (
    <A extends Pointable>(pointer: string, subject: A, value: unknown) => A
  ) & (
    (pointer: string) => Setter
  );
export const assign: (
    <A extends Pointable>(pointer: string, subject: A, value: unknown) => void
  ) & (
    (pointer: string) => Assigner
  );
export const unset: (
    <A extends Pointable>(pointer: string, subject: A) => A
  ) & (
    (pointer: string) => Unsetter
  );
export const remove: (
    (pointer: string, subject: Pointable) => void
  ) & (
    (pointer: string) => Remover
  );

export type Getter = (subject: Pointable) => unknown;
export type Setter = (
  <A extends Pointable>(subject: A, value: unknown) => A
) & (
  <A extends Pointable>(subject: A) => (value: unknown) => A
);
export type Assigner = (
  <A extends Pointable>(subject: A, value: unknown) => void
) & (
  <A extends Pointable>(subject: A) => (value: unknown) => void
);
export type Unsetter = <A extends Pointable>(subject: A) => A;
export type Remover = (subject: Pointable) => void;

export type Json = string | number | boolean | null | JsonObject | Json[];
export type JsonObject = {
  [property: string]: Json;
};

export type Pointable = JsonObject | Json[];
