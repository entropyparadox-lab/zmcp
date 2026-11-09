# zmcp 한국어 가이드

## 버전과 설치

- 패키지 버전: **1.1.1** (1.1.0에서 패치 업데이트)
- 검증 대상 컴파일러: **Zig 0.17.1**
- MCP 프로토콜: **2024-11-05**, UTF-8 줄바꿈 JSON-RPC stdio
- 공개 라이브러리 API는 변경하지 않았습니다.

먼저 `zig version`이 `0.17.1`인지 확인하세요. 전역 컴파일러를 바꿀 필요 없이
별도로 설치한 Zig 실행 파일의 절대 경로를 사용해도 됩니다.

배포된 실제 커밋의 전체 SHA를 `COMMIT_SHA`에 넣어 고정합니다. 아직 배포하지 않은
커밋 URL이나 존재하지 않는 `v1.1.1` 태그를 의존성에 넣지 마세요.

```sh
zig fetch --save https://github.com/entropyparadox-lab/zmcp/archive/COMMIT_SHA.tar.gz
```

`build.zig`에서 모듈을 연결합니다.

```zig
const dep = b.dependency("zmcp", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zmcp", dep.module("zmcp"));
```

도구는 `name`, `description`, `Params`, `call`을 가진 구조체로 정의하고
`Server.registerTool`로 등록합니다. 실행 가능한 전체 예제는
[`examples/server.zig`](../examples/server.zig)를 참고하세요.

## 로컬 검증

저장소 루트에서 실행합니다. 스모크 검증에는 Python 3도 필요합니다.

```sh
zig fmt --check src examples tests build.zig build.zig.zon
zig build test --summary all
python3 scripts/smoke_stdio.py --zig zig
zig build bench
```

스모크는 실제 프로세스에 `initialize`, `notifications/initialized`, `tools/list`,
`tools/call`을 보냅니다. 알림 무응답, 합계, 잘못된 인자의 `isError`, 256 KiB 문자열의
손실 없는 왕복을 확인하며 60초를 넘으면 자식 프로세스 그룹까지 종료합니다.
수동 실행은 `zig build run-example`이며 표준입력을 닫으면 종료합니다.
표준출력에는 JSON-RPC만 출력해야 합니다.

## 아카이브 소비

`build.zig.zon`의 `.paths`에는 `build.zig`가 참조하는 `src`, `examples`, `tests`가
모두 포함됩니다. 소스 체크아웃만 테스트하지 말고 `git archive`를 `zig fetch`로
가져온 뒤 별도 소비 프로젝트에서 `b.dependency(...).module("zmcp")`를 빌드하세요.
`zig fetch`가 출력한 패키지 해시와 전체 커밋 SHA를 함께 기록합니다.
`gateway` 같은 소비자는 그 정확한 커밋과 해시를 사용해야 합니다.
