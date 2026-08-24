/// 编译期开关：控制隐私空间功能是否编译进最终产物。
///
/// 默认 true（日常自用构建不用额外传参）。要分享给他人的构建，显式传 false：
///
///   flutter build apk --release --dart-define=VAULT_ENABLED=false \
///     --obfuscate --split-debug-info=build/symbols
///
/// 因为这是编译期常量，`if (kVaultEnabled)` 为 false 的分支在 release 编译时
/// 会被当作死代码消除，连同其中只被这个分支引用的类一起被 tree-shake 掉，
/// 不是运行时判断隐藏。`--obfuscate` 是顺手加的免费加固，不是本开关必需。
const bool kVaultEnabled = bool.fromEnvironment(
  'VAULT_ENABLED',
  defaultValue: true,
);
