---
name: commit-message-convention
description: Draft and review commit messages, branch names, and pull request descriptions for this repository. Use when Codex creates a commit, suggests or reviews a commit message, proposes a branch name, writes a pull request description, writes changelog-ready summaries, or checks whether any of those are acceptable.
---

# Change Convention

## Overview

Use this skill whenever preparing or validating a commit message, branch name, or pull request description for this repository. A valid commit message must use one approved type and the format `type(scope): subject`.

## Required Format

Use this header format:

```text
type(scope): subject
```

Requirements:

- Use exactly one approved type from the list below.
- Include a non-empty scope in parentheses. Choose the smallest meaningful subsystem, package, module, generator, test area, or documentation area, such as `boom`, `rocket`, `chipyard`, `docs`, `ci`, or `build`.
- Add a colon and one space after the scope.
- Write a concise subject that states the change in imperative or descriptive style.
- Do not end the subject with a period.
- Use a body when the change needs rationale, risk notes, verification details, or context that does not fit in the subject.

## Approved Types

- `fix`: 修复代码库中的 bug。
- `feat`: 在代码库中新增功能。
- `build`: 修改项目构建系统，例如依赖库、外部接口、Node 版本或类似构建输入。
- `chore`: 修改非业务性代码，例如构建流程、工具配置、维护脚本或仓库管理内容。
- `ci`: 修改持续集成流程，例如 Travis、Jenkins、GitHub Actions 或其他工作流配置。
- `docs`: 修改文档，例如 README、API 文档、设计说明或注释性文档。
- `style`: 修改代码样式，例如缩进、空格、空行、格式化，不改变逻辑。
- `refactor`: 重构代码，例如修改结构、变量名、函数名或拆分代码，不改变功能逻辑。
- `perf`: 有限的性能参数调优。性能功能应使用 `feat`，性能 bug 修复应使用 `fix`。
- `test`: 修改测试用例，例如添加、删除、修正或重构测试。
- `power`: 功耗优化。
- `area`: 面积优化。
- `timing`: 时序优化。
- `submodule`: 更新 Git submodule 引用。

## Body and Footers

Use a body when the motivation, expected effect, risk, or verification does not fit in the subject. Separate the header, body, and footer section with blank lines.

Add only the footers that apply. Do not invent an issue, author, URL, AI tool, or model name.

- For an issue-related change, add `Fixes #<issue-number>` on its own line. A pull request related to an issue must include this line so GitHub can link and close the issue.
- When Codex materially assists in generating commit or pull request content, resolve the active model ID before writing the trailer. Use the first available source in this order:
  1. The current Codex client configuration's top-level `model` value (normally `~/.codex/config.toml`).
  2. The exact model ID supplied by the current runtime or system context.
- Add the concrete result as `Assisted-by: Codex:<model-id>`. Never leave a placeholder literal or hardcode a model version in this skill. If neither source is available, omit this trailer rather than guessing.
- When another person co-authors the change, add `Co-authored-by: <name> <email>`.
- When relevant external discussions, reports, or papers exist, add `Link: <url>` as the final footer.
- Preserve other valid trailers, such as `Signed-off-by`, when supplied.

## Branch Names

When proposing or creating a branch, use `type-scope-description`.

- Use an approved type and keep it consistent with the planned commit type.
- Use a narrow, lowercase, hyphen-separated scope and description.
- Example: `fix-boom-recovery-priority`.

## Pull Request Descriptions

Describe the motivation and expected effect of the change. Include the applicable issue, AI-use, co-author, and link footers from the rules above. Keep `Fixes #<issue-number>` on a separate line.

## Workflow

When drafting a commit message:

1. Inspect the actual diff or user-described change before choosing a type.
2. Select the most specific approved type. Prefer `power`, `area`, or `timing` over generic `perf` when the change is specifically about those hardware quality targets.
3. Choose a narrow scope from the touched component, not a broad repository label unless the change is truly cross-cutting.
4. Draft the header in the required format.
5. Resolve the active model ID using the precedence above, then add applicable footers.

When reviewing a proposed commit message:

- Reject messages whose type is not in the approved list.
- Reject messages missing the `scope`.
- Reject messages missing the `: ` separator.
- Reject messages with an empty or vague subject.
- Flag missing footers that are required by known issue, AI-use, co-author, or external-reference context.
- Flag malformed footer tags or a `Link:` tag that is not last.
- Suggest a corrected message instead of only pointing out the violation.

## Examples

```text
fix(boom): handle branch recovery after exception redirect

feat(chipyard): add configurable harness clock divider

build(deps): update verilator integration flags

docs(readme): clarify FireSim setup requirements

power(rocket): gate multiplier clock when idle

area(cache): reduce metadata array width

timing(tilelink): pipeline manager response path

submodule(rocket-chip): update rocket-chip revision
```

## Complete Example

```text
fix(some-module): fix some bug

The original design has a bug that blabla.

This commit fixes that by doing blabla.

Fixes #123456
Assisted-by: Codex:<model-id>
Co-authored-by: Another Author <another.author@example.com>
Link: https://url.to.related.information
```
