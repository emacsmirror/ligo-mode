// This might seem like it's covered by induction with closure-2.ligo
// But it exists to prevent a regression on the bug patched by: 
// https://gitlab.com/ligolang/ligo/commit/faf3bbc06106de98189f1c1673bd57e78351dc7e

function foobar(const i : int) : int is
  const j : int = 3 ;
  const k : int = 4 ;
  function toto(const l : int) : int is
    block { skip } with i + j + k + l;
  block { skip } with toto(42)