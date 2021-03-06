/* Let's inline `h_plus_one` and see if the contract
   gets smaller and consumes less gas */

type a_complex_record = {
  complex: int,
  record: int,
  that: int,
  has: int,
  many: int,
  fields: int,
  and_some: int,
  counter: int
};

[@inline]
let plus_one = (r: a_complex_record) => {...r, counter: r.counter + 1};

let main = ((p, s): (int, a_complex_record)) =>
  ([] : list(operation), plus_one(plus_one(s)));
