// XMLHttpRequest for Node, built on fetch.
//
// elm/http sends requests with the browser's XMLHttpRequest, which Node
// doesn't have. The server runtime defines this one globally when a session
// starts, unless the process already has one, so a program's HTTP requests
// work on the server as they do in the page.
//
// It covers what elm/http uses (events, headers, timeouts, text and binary
// bodies, form data, progress and abort) and follows the standard for the
// rest, so other code that finds it works too. The differences come from
// running on a server: there's no page to resolve a relative URL against, so
// URLs must be absolute; there are no cookies to send, so `withCredentials`
// does nothing; and nothing is cross-origin, so there's no CORS.

const UNSENT = 0;
const OPENED = 1;
const HEADERS_RECEIVED = 2;
const LOADING = 3;
const DONE = 4;

// Browsers fire download progress at most this often.
const PROGRESS_MS = 50;

const RESPONSE_TYPES = new Set(["", "text", "arraybuffer", "blob", "json", "document"]);
const STANDARD_METHODS = new Set(["DELETE", "GET", "HEAD", "OPTIONS", "POST", "PUT"]);

class ProgressEvent extends Event {
  constructor(type, { loaded = 0, total = 0, lengthComputable = false } = {}) {
    super(type);
    this.loaded = loaded;
    this.total = total;
    this.lengthComputable = lengthComputable;
  }
}

// Listeners first, then the `onload = ...` style of handler. Like a
// listener's, a handler's exception doesn't stop the request.
function fire(target, type, loaded = 0, length = NaN) {
  const known = Number.isFinite(length);
  const event = type === "readystatechange" ? new Event(type) : new ProgressEvent(type, { loaded, total: known ? length : 0, lengthComputable: known });
  target.dispatchEvent(event);
  const handler = target[`on${type}`];
  if (typeof handler !== "function") return;
  try {
    handler.call(target, event);
  } catch (error) {
    process.nextTick(() => {
      throw error;
    });
  }
}

class XMLHttpRequestUpload extends EventTarget {
  onloadstart = null;
  onprogress = null;
  onabort = null;
  onerror = null;
  onload = null;
  ontimeout = null;
  onloadend = null;
}

export class XMLHttpRequest extends EventTarget {
  static UNSENT = UNSENT;
  static OPENED = OPENED;
  static HEADERS_RECEIVED = HEADERS_RECEIVED;
  static LOADING = LOADING;
  static DONE = DONE;

  onloadstart = null;
  onprogress = null;
  onabort = null;
  onerror = null;
  onload = null;
  ontimeout = null;
  onloadend = null;
  onreadystatechange = null;

  /** In milliseconds, from `send` to the end of the response. 0 waits forever. */
  timeout = 0;
  /** Does nothing. Requests from the server have no cookies to send. */
  withCredentials = false;
  upload = new XMLHttpRequestUpload();

  #state = UNSENT;
  #type = "";
  #method = "GET";
  #url = null;
  #headers = new Headers();
  #sent = false;
  #uploading = false;
  #response = null; // The fetch Response, once its headers are in.
  #chunks = [];
  #loaded = 0;
  #bytes = null; // The chunks joined, when asked for.
  #value = undefined; // `response` for the types that are only read once.
  #controller = null;
  #timer = null;
  #request = 0; // Counts up on open and abort, so a fetch they replaced is ignored.

  get readyState() {
    return this.#state;
  }

  get responseType() {
    return this.#type;
  }

  set responseType(type) {
    if (RESPONSE_TYPES.has(type)) this.#type = type;
  }

  get status() {
    return this.#response?.status ?? 0;
  }

  get statusText() {
    return this.#response?.statusText ?? "";
  }

  get responseURL() {
    return this.#response?.url ?? "";
  }

  get responseText() {
    if (this.#type !== "" && this.#type !== "text") {
      throw new DOMException(`responseText is only there when responseType is "" or "text", not "${this.#type}"`, "InvalidStateError");
    }
    return this.#text();
  }

  get response() {
    if (this.#type === "" || this.#type === "text") return this.#text();
    if (this.#state !== DONE || !this.#response) return null;
    if (this.#value === undefined) {
      const bytes = this.#received();
      if (this.#type === "arraybuffer") this.#value = bytes.buffer;
      else if (this.#type === "blob") this.#value = new Blob([bytes], { type: this.#response.headers.get("content-type") ?? "" });
      else if (this.#type === "json") this.#value = parseJson(new TextDecoder().decode(bytes));
      else this.#value = null; // There's no DOM to parse a document into.
    }
    return this.#value;
  }

  getResponseHeader(name) {
    return this.#response?.headers.get(name) ?? null;
  }

  getAllResponseHeaders() {
    let all = "";
    for (const [name, value] of this.#response?.headers ?? []) all += `${name}: ${value}\r\n`;
    return all;
  }

  open(method, url, async = true) {
    if (async === false) {
      throw new DOMException("Synchronous requests aren't supported on the server", "InvalidAccessError");
    }
    let parsed;
    try {
      parsed = new URL(url);
    } catch {
      throw new DOMException(`${url} isn't an absolute URL. On the server there's no page to resolve it against`, "SyntaxError");
    }
    this.#cancel();
    this.#method = STANDARD_METHODS.has(String(method).toUpperCase()) ? String(method).toUpperCase() : String(method);
    this.#url = parsed;
    this.#headers = new Headers();
    this.#sent = false;
    this.#uploading = false;
    this.#forget();
    if (this.#state !== OPENED) {
      this.#state = OPENED;
      fire(this, "readystatechange");
    }
  }

  setRequestHeader(name, value) {
    if (this.#state !== OPENED || this.#sent) {
      throw new DOMException("Headers can only be set between open and send", "InvalidStateError");
    }
    this.#headers.append(name, value);
  }

  send(body = null) {
    if (this.#state !== OPENED || this.#sent) {
      throw new DOMException("send needs open first, and only once per open", "InvalidStateError");
    }
    if (this.#method === "GET" || this.#method === "HEAD") body = null;
    this.#sent = true;
    const request = this.#request;
    fire(this, "loadstart");
    if (request !== this.#request) return; // A loadstart listener called abort or open.
    if (this.timeout > 0) this.#timer = setTimeout(() => this.#fail(request, "timeout"), this.timeout);
    this.#run(request, toBody(body)).catch(() => this.#fail(request, "error"));
  }

  abort() {
    this.#cancel();
    if ((this.#state === OPENED && this.#sent) || this.#state === HEADERS_RECEIVED || this.#state === LOADING) {
      this.#error("abort");
    }
    if (this.#state === DONE) {
      this.#state = UNSENT;
      this.#forget();
    }
  }

  async #run(request, body) {
    const controller = (this.#controller = new AbortController());
    const headers = new Headers(this.#headers);
    // Form data's size and boundary are only known once it's encoded.
    if (body instanceof FormData) {
      const encoded = new Response(body);
      if (!headers.has("content-type")) headers.set("content-type", encoded.headers.get("content-type"));
      body = new Uint8Array(await encoded.arrayBuffer());
      if (request !== this.#request) return;
    }
    const size = byteLength(body);
    if (body !== null) {
      this.#uploading = true;
      fire(this.upload, "loadstart", 0, size);
      if (request !== this.#request) return;
    }

    const response = await fetch(this.#url, { method: this.#method, headers, body, signal: controller.signal });
    if (request !== this.#request) return;
    // The whole body has gone once the response starts.
    if (this.#uploading) {
      this.#uploading = false;
      fire(this.upload, "progress", size, size);
      fire(this.upload, "load", size, size);
      fire(this.upload, "loadend", size, size);
      if (request !== this.#request) return;
    }
    this.#response = response;
    this.#state = HEADERS_RECEIVED;
    fire(this, "readystatechange");

    // Content-Length counts the bytes as sent, and fetch unzips them.
    const length = response.headers.has("content-encoding") ? NaN : Number(response.headers.get("content-length") ?? NaN);
    let reported = performance.now();
    for await (const chunk of response.body ?? []) {
      if (request !== this.#request) return;
      this.#chunks.push(chunk);
      this.#loaded += chunk.byteLength;
      this.#bytes = null;
      if (this.#state === HEADERS_RECEIVED) {
        this.#state = LOADING;
        fire(this, "readystatechange");
      }
      if (performance.now() - reported >= PROGRESS_MS) {
        reported = performance.now();
        fire(this, "progress", this.#loaded, length);
      }
    }
    if (request !== this.#request) return;
    this.#finish();
    fire(this, "progress", this.#loaded, length);
    this.#state = DONE;
    this.#sent = false;
    fire(this, "readystatechange");
    fire(this, "load", this.#loaded, length);
    fire(this, "loadend", this.#loaded, length);
  }

  #fail(request, type) {
    if (request !== this.#request) return;
    this.#cancel();
    this.#error(type);
  }

  // Stops the request in flight, if there is one, without telling anyone.
  #cancel() {
    this.#request++;
    this.#controller?.abort();
    this.#finish();
  }

  #finish() {
    clearTimeout(this.#timer);
    this.#timer = null;
    this.#controller = null;
  }

  #error(type) {
    const uploading = this.#uploading;
    this.#state = DONE;
    this.#sent = false;
    this.#uploading = false;
    this.#forget();
    fire(this, "readystatechange");
    if (uploading) {
      fire(this.upload, type);
      fire(this.upload, "loadend");
    }
    fire(this, type);
    fire(this, "loadend");
  }

  #forget() {
    this.#response = null;
    this.#chunks = [];
    this.#loaded = 0;
    this.#bytes = null;
    this.#value = undefined;
  }

  #received() {
    if (!this.#bytes) {
      this.#bytes = new Uint8Array(this.#loaded);
      let offset = 0;
      for (const chunk of this.#chunks) {
        this.#bytes.set(chunk, offset);
        offset += chunk.byteLength;
      }
    }
    return this.#bytes;
  }

  #text() {
    if (this.#state !== LOADING && this.#state !== DONE) return "";
    return decoder(this.#response?.headers.get("content-type")).decode(this.#received());
  }
}

// What fetch takes, the way XMLHttpRequest reads it: anything that isn't a
// body already is sent as a string, and no body is null.
function toBody(body) {
  if (body === null || body === undefined) return null;
  if (typeof body === "string" || body instanceof Blob || body instanceof FormData || body instanceof URLSearchParams) return body;
  if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return body;
  return String(body);
}

function byteLength(body) {
  if (body === null) return 0;
  if (typeof body === "string") return Buffer.byteLength(body);
  if (body instanceof URLSearchParams) return Buffer.byteLength(body.toString());
  if (body instanceof Blob) return body.size;
  return body.byteLength;
}

// Text is decoded with the charset the response names, or as UTF-8.
function decoder(contentType) {
  const charset = /;\s*charset\s*=\s*"?([^";\s]+)/i.exec(contentType ?? "")?.[1];
  try {
    return new TextDecoder(charset ?? "utf-8");
  } catch {
    return new TextDecoder();
  }
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
