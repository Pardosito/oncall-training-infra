# Turns Cognito's default managed login settings into Carbon's g100 (dark) theme (D-34).
# Input: describe-managed-login-branding --return-merged-resources | .ManagedLoginBranding.Settings
# Regenerate: see the header of terraform/foundation/cognito-branding.tf.
def c($hex): $hex + "ff";
. as $d
| .categories.global.colorSchemeMode = "DARK"
| .categories.global.spacingDensity = "REGULAR"
| .componentClasses.buttons.borderRadius = 0
| .componentClasses.input.borderRadius = 0
| .componentClasses.dropDown.borderRadius = 0
| .components.form.borderRadius = 0
| .components.alert.borderRadius = 0
| .components.pageBackground.image.enabled = false
| .components.pageBackground.darkMode.color = c("161616")
| .components.form.darkMode = {backgroundColor: c("262626"), borderColor: c("393939")}
| .components.form.logo = {enabled: true, location: "CENTER", position: "TOP", formInclusion: "IN"}
| .components.pageText.darkMode = {headingColor: c("f4f4f4"), bodyColor: c("c6c6c6"), descriptionColor: c("c6c6c6")}
| .components.primaryButton.darkMode = {
    defaults: {backgroundColor: c("0f62fe"), textColor: c("ffffff")},
    hover: {backgroundColor: c("0050e6"), textColor: c("ffffff")},
    active: {backgroundColor: c("002d9c"), textColor: c("ffffff")},
    disabled: {backgroundColor: c("525252"), borderColor: c("525252")}}
| .components.secondaryButton.darkMode = {
    defaults: {backgroundColor: c("6f6f6f"), borderColor: c("6f6f6f"), textColor: c("ffffff")},
    hover: {backgroundColor: c("606060"), borderColor: c("606060"), textColor: c("ffffff")},
    active: {backgroundColor: c("393939"), borderColor: c("393939"), textColor: c("ffffff")}}
| .componentClasses.input.darkMode = {defaults: {backgroundColor: c("393939"), borderColor: c("6f6f6f")}, placeholderColor: c("a8a8a8")}
| .componentClasses.inputLabel.darkMode.textColor = c("c6c6c6")
| .componentClasses.inputDescription.darkMode.textColor = c("a8a8a8")
| .componentClasses.link.darkMode = {defaults: {textColor: c("78a9ff")}, hover: {textColor: c("a6c8ff")}}
| .componentClasses.focusState.darkMode.borderColor = c("ffffff")
| .componentClasses.divider.darkMode.borderColor = c("393939")
| .componentClasses.optionControls.darkMode = {
    defaults: {backgroundColor: c("262626"), borderColor: c("8d8d8d")},
    selected: {backgroundColor: c("f4f4f4"), foregroundColor: c("161616")}}
| .componentClasses.statusIndicator.darkMode = {
    error: {backgroundColor: c("262626"), borderColor: c("fa4d56"), indicatorColor: c("fa4d56")},
    pending: {indicatorColor: c("78a9ff")},
    success: {backgroundColor: c("262626"), borderColor: c("42be65"), indicatorColor: c("42be65")},
    warning: {backgroundColor: c("262626"), borderColor: c("f1c21b"), indicatorColor: c("f1c21b")}}
| .components.alert.darkMode.error = {backgroundColor: c("262626"), borderColor: c("fa4d56")}
| .componentClasses.dropDown.darkMode = {
    defaults: {itemBackgroundColor: c("393939")},
    hover: {itemBackgroundColor: c("4c4c4c"), itemBorderColor: c("4c4c4c"), itemTextColor: c("f4f4f4")},
    match: {itemBackgroundColor: c("393939"), itemTextColor: c("78a9ff")}}
| .components.favicon.enabledTypes = ["SVG"]
