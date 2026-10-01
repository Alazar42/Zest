const zest = @import("zest");
const products_ctrl = @import("../controllers/products.zig");

/// Registers all product endpoints on the provided router or route group.
pub fn register(g: *zest.Group) !void {
    try g.get("", products_ctrl.getAll);
    try g.get("/:id", products_ctrl.getById);
    try g.post("", products_ctrl.create);
    try g.delete("/:id", products_ctrl.deleteProduct);
}
