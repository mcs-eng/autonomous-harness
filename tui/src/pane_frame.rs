//! Presentation insets live outside the tmux layout tree. Its splits and named layouts
//! remain unchanged; the terminal, cursor, copy mode and mouse share this content rectangle.

use ratatui::layout::Rect;
use crate::layout::Status;

#[derive(Clone, Copy, Debug)]
pub struct Frame { pub surface: Rect, pub content: Rect, pub title: Option<Rect>, pub outline: Option<Rect> }

pub fn frame(tile: Rect, canvas: Rect, status: Status) -> Frame {
    let mut outer = tile;
    // A small pane gives its cells to the program. Larger panes keep one-cell outer space.
    if tile.width >= 12 && canvas.width >= 40 {
        if tile.x == canvas.x { outer.x += 1; outer.width -= 1; }
        if tile.right() == canvas.right() { outer.width = outer.width.saturating_sub(1); }
    }
    if tile.height >= 8 && canvas.height >= 12 {
        // With top/bottom status, tmux borrows the divider row for a pane title. Leave
        // that row as a gutter and draw the title inside the surface instead.
        if tile.y == canvas.y || status == Status::Top { outer.y += 1; outer.height -= 1; }
        if tile.bottom() == canvas.bottom() || status == Status::Bottom { outer.height = outer.height.saturating_sub(1); }
    }
    // Each normal-sized tile owns its outline; the layout's divider remains a gap.
    // A lone or zoomed pane, and compact panes, keep their content space instead.
    let outline = (tile != canvas && tile.width >= 12 && canvas.width >= 40
        && tile.height >= 8 && canvas.height >= 12).then_some(outer);
    let surface = if outline.is_some() {
        Rect::new(outer.x + 1, outer.y + 1, outer.width - 2, outer.height - 2)
    } else { outer };
    let title = (surface.height > 1 && status != Status::Off).then(|| Rect::new(surface.x,
        if status == Status::Bottom { surface.bottom() - 1 } else { surface.y }, surface.width, 1));
    let mut content = surface;
    if title.is_some() {
        if status == Status::Top { content.y += 1; }
        content.height -= 1;
    }
    if content.width >= 12 { content.x += 1; content.width -= 2; }
    if content.height >= 10 { content.y += 1; content.height -= 2; }
    Frame { surface, content, title, outline }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn small_panes_keep_usable_cells_and_every_rect_stays_inside() {
        for w in 1..=100 { for h in 1..=40 { for status in [Status::Off, Status::Top, Status::Bottom] {
            let tile = Rect::new(3, 2, w, h);
            let canvas = Rect::new(0, 0, w + 8, h + 6);
            let f = frame(tile, canvas, status);
            assert_eq!(f.surface.intersection(tile), f.surface);
            assert_eq!(f.content.intersection(f.surface), f.content);
            assert!(f.content.width > 0 && f.content.height > 0);
            if let Some(title) = f.title { assert_eq!(title.intersection(f.content).height, 0); }
            if let Some(outline) = f.outline {
                assert_eq!(outline.intersection(tile), outline);
                assert!(outline.x < f.surface.x && outline.y < f.surface.y);
                assert!(outline.right() > f.surface.right() && outline.bottom() > f.surface.bottom());
            }
        } } }
    }

    #[test]
    fn stacked_and_side_by_side_surfaces_leave_divider_gaps() {
        let canvas = Rect::new(0, 0, 120, 40);
        let left = frame(Rect::new(0, 0, 59, 40), canvas, Status::Top);
        let right = frame(Rect::new(60, 0, 60, 40), canvas, Status::Top);
        assert_eq!(right.outline.unwrap().x - left.outline.unwrap().right(), 1);
        assert_eq!(left.outline.unwrap().intersection(right.outline.unwrap()).width, 0);
        assert_eq!(left.outline.unwrap().intersection(right.surface).width, 0);
        assert_eq!(right.outline.unwrap().intersection(left.surface).width, 0);
        let top = frame(Rect::new(0, 0, 120, 20), canvas, Status::Top);
        let bottom = frame(Rect::new(0, 20, 120, 20), canvas, Status::Top);
        assert_eq!(bottom.outline.unwrap().y - top.outline.unwrap().bottom(), 1);
        assert_eq!(top.outline.unwrap().intersection(bottom.outline.unwrap()).height, 0);
        assert_eq!(top.outline.unwrap().intersection(bottom.surface).height, 0);
        assert_eq!(bottom.outline.unwrap().intersection(top.surface).height, 0);
        assert!(top.content.y > top.title.unwrap().y);
        assert!(frame(canvas, canvas, Status::Top).outline.is_none());
        // Short inner tiles share a title row without the normal outer gutter.
        assert!(frame(Rect::new(20, 20, 40, 5), canvas, Status::Top).outline.is_none());
    }
}
