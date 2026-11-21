from moonraker.components.update_manager.git_deploy import GitRepo


def _is_kalico(url):
    url = (url or "").strip().lower().rstrip("/")
    if url.endswith(".git"):
        url = url[:-4]
    return url == "https://github.com/flashforge-c5-modding-group/kalico"


_original_check_warnings = GitRepo._check_warnings


if not getattr(_original_check_warnings, "_kalico_runtime_patch", False):

    def _patched_check_warnings(self):
        _original_check_warnings(self)

        if _is_kalico(self.upstream_url):
            self.repo_anomalies[:] = [
                warning for warning in self.repo_anomalies
                if not warning.startswith(
                    "Repo not on official remote/branch, expected:"
                )
                and not warning.startswith("Unofficial remote url:")
            ]

    _patched_check_warnings._kalico_runtime_patch = True
    GitRepo._check_warnings = _patched_check_warnings


class KalicoRuntimePatch:
    async def initialize(self):
        pass


def load_component(config):
    return KalicoRuntimePatch()
