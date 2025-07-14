# CodeCompanion Tools - Simplified

This is a simplified version of codecompanion-tools that maintains all functionality while improving code clarity and cross-platform compatibility.

## Key Improvements

### Code Simplification
- Removed redundant error handling with pcall where not necessary
- Eliminated forward declarations and unused variables
- Simplified function definitions and comments
- Reduced code duplication
- Consolidated type definitions

### Cross-Platform Compatibility
- Improved path normalization for Windows/Unix compatibility
- Cross-platform root directory detection
- Dynamic path separator handling
- Better file path joining using package.config

### Code Quality
- All comments and documentation converted to English
- Consistent code style throughout
- Removed obsolete files and redirections
- Cleaner function signatures
- More descriptive variable names

### Maintained Functionality
- ✅ Model toggling with sequence and models modes
- ✅ Rule file auto-detection and management
- ✅ Chat reference synchronization
- ✅ Buffer lifecycle management
- ✅ All original configuration options
- ✅ Backward compatibility

## Files Changed

1. **lua/codecompanion/_extensions/codecompanion-tools/init.lua** - Main extension entry point
2. **lua/codecompanion_tools/init.lua** - Backward compatibility wrapper
3. **lua/codecompanion_tools/model_toggle.lua** - Model switching functionality
4. **lua/codecompanion_tools/rule.lua** - Rule file management
5. **examples/usage.lua** - Usage documentation
6. **lua/codecompanion_tools/extensions/codecompanion.lua** - Removed (obsolete)

## Usage

The extension works exactly the same as before. Configuration and usage remain unchanged, but the code is now cleaner and more maintainable.

```lua
require("codecompanion").setup({
  extensions = {
    ["codecompanion-tools"] = {
      opts = {
        rules = { enabled = true },
        model_toggle = { enabled = true }
      }
    }
  }
})
```