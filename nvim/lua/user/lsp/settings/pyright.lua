local util = require('lspconfig/util')

return {
  root_dir = function(fname)
    return util.root_pattern(".git", "setup.cfg", "pyproject.toml")(fname) or util.path.dirname(fname)
  end
}
