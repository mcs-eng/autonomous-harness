//! One reader for keyboard input and asynchronous capability replies. Input uses the
//! pinned Crossterm decoder, so negotiation cannot consume keys, paste or mouse events.
use crossterm::event::{Event, KeyboardEnhancementFlags};
use std::time::{Duration, Instant};

#[path = "term_input_parse.rs"]
mod parse;

#[allow(dead_code)]
#[derive(Debug, PartialEq)]
enum InternalEvent { Event(Event), CursorPosition(u16, u16), KeyboardEnhancementFlags(KeyboardEnhancementFlags), PrimaryDeviceAttributes }

#[derive(Debug, PartialEq)]
enum Item { Input(Event), Terminal(Option<String>) }

#[derive(Default)]
struct Decoder { pending: Vec<u8> }
impl Decoder {
    fn push(&mut self, bytes: &[u8], more: bool) -> Vec<Item> {
        let mut out = Vec::new();
        for b in bytes {
            self.pending.push(*b);
            let p = &self.pending;
            // XDA: DCS > | name ST. Hold only this prefix; ordinary Alt-P remains a key.
            if b"\x1bP>|".starts_with(p) { continue }
            if p.starts_with(b"\x1bP>|") && p.len() < 4096 {
                let end = if p.ends_with(b"\x1b\\") { Some(p.len() - 2) } else if p.ends_with(b"\x07") { Some(p.len() - 1) } else { None };
                if let Some(end) = end { out.push(Item::Terminal(Some(String::from_utf8_lossy(&p[4..end]).into_owned()))); self.pending.clear(); }
                continue;
            }
            // If the apparent XDA prefix turned out to be Alt-P, replay through the exact
            // byte decoder rather than letting its first event discard the following bytes.
            if p.starts_with(b"\x1bP") {
                let bytes = std::mem::take(&mut self.pending);
                for (i, b) in bytes.iter().enumerate() { self.pending.push(*b); self.parse(i + 1 < bytes.len(), &mut out); }
            } else { self.parse(true, &mut out); }
        }
        // Match Crossterm's read boundary: a short read ends a standalone Escape.
        // Waiting for an idle timer here folds a following prefix into an Alt key.
        if !more { out.extend(self.escape()); }
        out
    }
    fn parse(&mut self, more: bool, out: &mut Vec<Item>) {
        match parse::parse_event(&self.pending, more) {
            Ok(Some(InternalEvent::Event(event))) => { out.push(Item::Input(event)); self.pending.clear(); }
            Ok(Some(InternalEvent::PrimaryDeviceAttributes)) => { out.push(Item::Terminal(None)); self.pending.clear(); }
            Ok(Some(_)) | Err(_) => self.pending.clear(),
            Ok(None) => {},
        }
    }
    fn escape(&mut self) -> Vec<Item> {
        let mut out = Vec::new();
        if self.pending == b"\x1b" { self.parse(false, &mut out); }
        else if self.pending.len() < 4 && b"\x1bP>|".starts_with(&self.pending) {
            // A lone Alt-P is also a possible query prefix; give it the same escape delay.
            let bytes = std::mem::take(&mut self.pending);
            for (i, b) in bytes.iter().enumerate() { self.pending.push(*b); self.parse(i + 1 < bytes.len(), &mut out); }
        }
        out
    }
}

/// Blocking reader thread. The initial queries never delay drawing or shell startup;
/// terminal replies can arrive after ordinary input and do not become keystrokes.
pub fn read(keys: tokio::sync::mpsc::UnboundedSender<crate::event::Event>) {
    use std::os::fd::AsRawFd;
    let tty = if std::io::IsTerminal::is_terminal(&std::io::stdin()) { None } else { std::fs::OpenOptions::new().read(true).write(true).open("/dev/tty").ok() };
    let fd = tty.as_ref().map(AsRawFd::as_raw_fd).unwrap_or_else(|| std::io::stdin().as_raw_fd());
    let mut decoder = Decoder::default();
    let mut last = Instant::now();
    let mut buf = [0u8; 8192];
    loop {
        let mut pfd = libc::pollfd { fd, events: libc::POLLIN, revents: 0 };
        let n = unsafe { libc::poll(&mut pfd, 1, 50) };
        if n < 0 { if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted { continue } break }
        let items = if n == 0 {
            if last.elapsed() >= Duration::from_millis(50) { decoder.escape() } else { Vec::new() }
        } else {
            let n = unsafe { libc::read(fd, buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 { break }
            last = Instant::now();
            decoder.push(&buf[..n as usize], n as usize == buf.len())
        };
        for item in items {
            let event = match item {
                Item::Input(event) => crate::event::Event::Input(event),
                Item::Terminal(name) => {
                    if !crate::term_out::terminal_answer(name) { continue }
                    crate::event::Event::Apply(Box::new(|app| app.redraw_all = true))
                }
            };
            if keys.send(event).is_err() { return }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    #[test]
    fn query_replies_do_not_consume_interleaved_typeahead() {
        let mut decoder = Decoder::default();
        let mut items = Vec::new();
        for b in b"printf hello\r\x1bP>|tmux 3.5a\x1b\\\x1b[?1;2cWORLD" { items.extend(decoder.push(&[*b], true)); }
        let names: Vec<_> = items.iter().filter_map(|i| if let Item::Terminal(n) = i { Some(n.clone()) } else { None }).collect();
        assert_eq!(names, vec![Some("tmux 3.5a".into()), None]);
        let text: String = items.iter().filter_map(|i| match i { Item::Input(Event::Key(k)) => match k.code { KeyCode::Char(c) => Some(c), KeyCode::Enter => Some('\r'), _ => None }, _ => None }).collect();
        assert_eq!(text, "printf hello\rWORLD");
    }
    #[test]
    fn escape_at_a_read_boundary_does_not_take_the_next_prefix() {
        let mut decoder = Decoder::default();
        assert_eq!(decoder.push(b"\x1b", false), vec![Item::Input(Event::Key(KeyCode::Esc.into()))]);
        assert_eq!(decoder.push(b"\x02@", false), vec![
            Item::Input(Event::Key(KeyEvent::new(KeyCode::Char('b'), KeyModifiers::CONTROL))),
            Item::Input(Event::Key(KeyCode::Char('@').into())),
        ]);
        // Bytes from one terminal write still form Alt keys and CSI sequences.
        assert_eq!(decoder.push(b"\x1bp", false), vec![Item::Input(Event::Key(KeyEvent::new(KeyCode::Char('p'), KeyModifiers::ALT)))]);
        assert!(decoder.push(b"\x1b[", false).is_empty());
        assert_eq!(decoder.push(b"A", false), vec![Item::Input(Event::Key(KeyCode::Up.into()))]);
    }
    #[test]
    fn split_utf8_paste_and_modified_keys_use_the_input_decoder() {
        let mut decoder = Decoder::default();
        let mut items = Vec::new();
        let bytes = "é\x1b[1;5D\x1b[200~paste\n\x1b[?1;2c\x1b[201~\x1bPz";
        for b in bytes.bytes() { items.extend(decoder.push(&[b], true)); }
        assert_eq!(items, vec![Item::Input(Event::Key(KeyCode::Char('é').into())), Item::Input(Event::Key(KeyEvent::new(KeyCode::Left, KeyModifiers::CONTROL))), Item::Input(Event::Paste("paste\n\x1b[?1;2c".into())), Item::Input(Event::Key(KeyEvent::new(KeyCode::Char('P'), KeyModifiers::SHIFT | KeyModifiers::ALT))), Item::Input(Event::Key(KeyCode::Char('z').into()))]);
        assert!(decoder.push(b"\x1b", true).is_empty());
        assert_eq!(decoder.escape(), vec![Item::Input(Event::Key(KeyCode::Esc.into()))]);
        assert!(decoder.push(b"\x1bP", true).is_empty());
        assert_eq!(decoder.escape(), vec![Item::Input(Event::Key(KeyEvent::new(KeyCode::Char('P'), KeyModifiers::SHIFT | KeyModifiers::ALT)))]);
    }
}
