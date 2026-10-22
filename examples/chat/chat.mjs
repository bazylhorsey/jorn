// The chat room's server code. Each page runs its own session of the Elm
// program, and this passes what anyone says to every session, through the
// program's `say` and `hear` ports.
//
//   attachChat(server, { path: "/chat", program: Elm.Main });
//
// `examples/serve.mjs` runs it, and server/test/chat.mjs tests it.

import { attach } from "../../server/jorn.js";

export function attachChat(server, { path, program, log }) {
  const everyone = new Set(); // Each session's ports.
  const recent = []; // The last lines, for pages that join later.
  let guests = 0;

  function broadcast(line) {
    recent.push(line);
    if (recent.length > 100) recent.shift();
    for (const ports of everyone) ports.hear.send(line);
  }

  return attach(server, {
    path,
    program,
    log,
    // Names come from the server, so a page can't speak as someone else.
    flags: () => ({ name: `Guest ${++guests}`, recent: [...recent] }),
    onSession({ ports, flags }) {
      const say = (text) => broadcast({ name: flags.name, text: text.slice(0, 500) });
      ports.say.subscribe(say);
      everyone.add(ports);
      broadcast({ name: flags.name, joined: true });
      return () => {
        everyone.delete(ports);
        ports.say.unsubscribe(say);
        broadcast({ name: flags.name, left: true });
      };
    },
  });
}
