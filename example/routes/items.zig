const zest = @import("zest");
const items_ctrl = @import("../controllers/items.zig");

/// Registers all items routes on the provided router or route group.
pub fn register(g: *zest.Group) !void {
    try g.get("", items_ctrl.getAll);
    try g.get("/", items_ctrl.getAll);
    try g.get("/:id", items_ctrl.getById);
    try g.post("", items_ctrl.create);
    try g.post("/", items_ctrl.create);
    try g.delete("/:id", items_ctrl.deleteItem);
}
