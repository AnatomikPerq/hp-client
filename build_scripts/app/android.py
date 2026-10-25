import os
import shutil

from app.builder import Builder
from app.command_line import flutter_command, run_command

# Split APKs from GitHub releases. The App's updater picks the one of its own
# ABI by name: HyperClient-<version>-android-<abi>.apk.
ANDROID_ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")


class AndroidBuilder(Builder):
    def before_build(self):
        super().before_build()
        self.build_core()

    def keystore_properties(self) -> str:
        return os.path.join(self.project_dir, "keystore", "keystore.properties")

    def build_app(self):
        # Without the release key Gradle signs with the debug key, and such an
        # APK can never be updated by a signed one.
        if not os.path.isfile(self.keystore_properties()):
            raise FileNotFoundError(
                "Android release key missing: android/keystore/keystore.properties "
                "(readme/BUILD.md)"
            )
        marketing_version, _, build_number = self.read_version().partition("+")
        run_command(
            [
                flutter_command(),
                "build",
                "apk",
                "--release",
                "--split-per-abi",
                "--target-platform",
                "android-arm,android-arm64,android-x64",
                f"--build-number={build_number or self.build_number}",
                # Kotlin's incremental caches fail when the pub cache and the
                # checkout are on different drives (the subst drive the
                # Cyrillic workspace path needs, readme/BUILD.md).
                "--android-project-arg",
                "kotlin.incremental=false",
            ],
            cwd=self.root_dir,
        )
        outputs = os.path.join(self.root_dir, "build", "app", "outputs", "flutter-apk")
        for abi in ANDROID_ABIS:
            source = os.path.join(outputs, f"app-{abi}-release.apk")
            if not os.path.isfile(source):
                raise FileNotFoundError(f"Android package missing: {source}")
            shutil.copy2(
                source,
                os.path.join(
                    self.output_dir,
                    f"{self.project}-{marketing_version}-android-{abi}.apk",
                ),
            )
