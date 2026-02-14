APP_NAME = Glance
INSTALL_PATH = /Applications

all: build install register reset  ## Fully build and install

help:   ## Show this help
	@grep -E '^([a-zA-Z_-]+):.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "%-20s %s\n", $$1, $$2}'kk

build:  ## Build the Application in the `build` folder
	@echo "Building Quick Look extension..."
	@rm -rf build
	xcodebuild -scheme $(APP_NAME) -configuration Release -derivedDataPath build clean build
	@echo "Build complete"

install: ## Install the Application into `INSTALL_PATH` (`/Applications` by default)
	@echo "Installing to $(INSTALL_PATH)..."
	@rm -rf $(INSTALL_PATH)/$(APP_NAME).app
	@cp -R build/Build/Products/Release/$(APP_NAME).app $(INSTALL_PATH)/
	@echo "Installed to $(INSTALL_PATH)/$(APP_NAME).app"

register:  ## Register the QuickLook plugin with `pluginkit`
	@echo "Registering extension with system..."
	@pluginkit -a $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/QLPlugin.appex || true
	@echo "Registration complete"

reset:  ## Reset Quick Look system
	@echo "Resetting Quick Look..."
	@qlmanage -r
	@qlmanage -r cache
	@killall Finder 2>/dev/null || true
	@killall quicklookd 2>/dev/null || true
	@echo "Quick Look reset"

check:  ## Check whether Quick Look plugin is properly installed
	@echo "Checking extension status..."
	@echo ""
	@echo "Extension registration:"
	@pluginkit -m -v | grep -A3 -i $(APP_NAME) || echo "Not registered"
	@echo ""
	@echo "Installed location:"
	@ls -la $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/*.appex 2>/dev/null || echo "Not found"
	@echo ""

clean:  # Clean build artifcats
	@echo "Cleaning build artifacts..."
	@rm -rf build
	@rm -rf ~/Library/Developer/Xcode/DerivedData/$(APP_NAME)-*
	@echo "Clean complete"

uninstall: clean  # Uninstall the application from `INSTALL_PATH` (`/Applications`)
	@echo "Uninstalling..."
	@rm -rf $(INSTALL_PATH)/$(APP_NAME).app
	@pluginkit -r $(INSTALL_PATH)/$(APP_NAME).app/Contents/PlugIns/QLPlugin.appex 2>/dev/null || true
	@$(MAKE) reset
	@echo "Uninstalled"

.PHONY: help all build install register reset check clean uninstall
