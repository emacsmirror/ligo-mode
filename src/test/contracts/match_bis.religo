type storage = int;

/* variant defining pseudo multi-entrypoint actions */

type action =
  | Increment(int)
  | Decrement(int);

let add = ((a: int), (b: int)) => a + b;

let subtract = ((a: int), (b: int)) => a - b;

/* real entrypoint that re-routes the flow based on the action provided */

let main = ((p: action), storage) => {
  let storage =
    switch (p) {
    | Increment(n) => add(storage, n)
    | Decrement(n) => subtract(storage, n)
    };
  (([]: list(operation)), storage);
};
