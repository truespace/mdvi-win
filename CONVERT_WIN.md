# Windows PowerShell 이식 계획

## 프로젝트 구조

```
mdvi/
├── Cargo.toml          # 의존성 정의
└── src/
    ├── main.rs         # CLI 파싱 (clap), 진입점
    ├── app.rs          # TUI 앱 로직: 이벤트 처리, 이미지 로딩/렌더링, 상태 관리
    └── renderer.rs     # Markdown → ratatui Lines/Spans 변환 (순수 렌더링)
```

---

## 문제 목록

### 1. `file://` URI 경로 처리 — 버그 [우선순위: 🔴 필수]

**위치**: `src/app.rs:1920-1921`

```rust
if let Some(path) = src.strip_prefix("file://") {
    return Some(ResolvedImageSource::Local(PathBuf::from(path)));
}
```

**문제**: Windows의 file URI는 `file:///C:/path/to/img.png` 형태.  
`strip_prefix("file://")` 후 `/C:/path/to/img.png` 가 되는데, Windows에서 이 경로는
현재 드라이브 루트 상대경로로 해석되어 잘못된 파일을 가리킨다.

**수정 방향**:
- `file:///` (슬래시 3개) strip 후 남은 경로 앞 슬래시 제거
- 또는 `#[cfg(windows)]`로 분기하여 Windows 경로 정규화

---

### 2. `Picker::from_query_stdio()` 이미지 프로토콜 자동감지 — 타임아웃 가능 [우선순위: 🟡 권장]

**위치**: `src/app.rs:1358`

```rust
let mut picker = Picker::from_query_stdio()
    .unwrap_or_else(|_| Picker::from_fontsize((10, 20)));
```

**문제**: 터미널에 ESC 쿼리 시퀀스를 보내고 응답을 읽는 방식으로 이미지 프로토콜을 감지.
구형 PowerShell 호스트(conhost.exe)에서는 응답이 없어 쿼리가 타임아웃될 수 있다.
실패 시 `from_fontsize` 폴백으로 앱은 동작하지만 이미지 크기 계산이 부정확해진다.

**수정 방향**:
- Windows 빌드 시 `from_query_stdio()` skip, `from_fontsize` 직행
- 또는 Windows Terminal 감지 후 조건부 실행

---

### 3. 이미지 프로토콜 호환성 — 기능 제한 [우선순위: 🟡 권장]

| 프로토콜 | Windows Terminal | PowerShell (conhost) |
|---------|-----------------|----------------------|
| Halfblocks | ✅ 동작 | ✅ 동작 |
| Sixel | ⚠️ Windows Terminal 1.22+ 일부 지원 | ❌ 미지원 |
| Kitty | ❌ | ❌ |
| iTerm2 | ❌ | ❌ |

**수정 방향**:
- `ImageProtocol::Auto`일 때 Windows에서 Halfblocks로 명시 fallback
- 또는 문서/README에 `--image-protocol halfblocks` 권장 명시

---

### 4. `crossterm` raw mode — 구형 Windows 미지원 [우선순위: 🟢 선택]

**위치**: `src/app.rs:1332-1335`

```rust
enable_raw_mode().context("failed to enable raw mode")?;
execute!(stdout, EnterAlternateScreen)?;
```

**문제**: Windows 10 버전 1903 미만 또는 VT 처리 모드 비활성화 환경에서 `enable_raw_mode` 실패.
crossterm은 Windows를 공식 지원하므로 최신 Windows 10/11에서는 문제 없음.

**수정 방향**:
- 에러 메시지에 "Windows 10 1903 이상 필요" 안내 추가

---

### 5. `arboard` 클립보드 — 조건부 동작 [우선순위: 🟢 선택]

**위치**: `src/app.rs:769`

```rust
Clipboard::new().and_then(|mut cb| cb.set_text(...))
```

**상태**: `arboard`는 Windows Win32 API를 지원하며, 현재 코드는 메인 스레드에서 호출하므로
대부분 정상 동작. 실패 시 `clipboard copy failed: {err}` 메시지로 graceful 처리되어 있음.

**수정 방향**: 별도 수정 불필요. 테스트 후 이상 시 재검토.

---

## 수정 우선순위 요약

| 순서 | 파일 | 위치 | 내용 | 난이도 |
|------|------|------|------|--------|
| 1 | `app.rs` | L1920 | `file://` URI → Windows 경로 변환 버그 | 낮음 |
| 2 | `app.rs` | L1358 | Windows에서 이미지 프로토콜 자동감지 skip/fallback | 낮음 |
| 3 | `app.rs` | L1358 | Auto 프로토콜 → Windows에서 Halfblocks fallback 명시화 | 낮음 |
| 4 | `app.rs` | L1333 | 구형 Windows 에러 메시지 개선 | 낮음 |
| 5 | `app.rs` | L769 | 클립보드 동작 검증 (테스트 후 판단) | - |

---

## 빌드 검증 결과

### `x86_64-pc-windows-gnu` 크로스 컴파일 (2026-04-02)

**환경**: macOS aarch64, Rust 1.94.1, mingw-w64 14.0.0  
**타겟**: `x86_64-pc-windows-gnu`  
**결과**: ✅ **컴파일 오류 없음** — 모든 의존성 포함 빌드 성공

컴파일러 수준에서의 OS 종속 코드는 없음. 남은 문제들은 모두 **런타임 동작** 관련이며,
실제 Windows 환경에서 실행 테스트를 통해 검증 필요.

---

## 의존성 Windows 호환성 현황

| 크레이트 | Windows 지원 | 비고 |
|---------|-------------|------|
| crossterm 0.28 | ✅ | Windows Console API + VT 처리 |
| ratatui 0.29 | ✅ | crossterm 백엔드 |
| arboard 3.6 | ✅ | Win32 클립보드 API |
| ratatui-image 8.1 | ⚠️ | 프로토콜 자동감지 주의 |
| syntect 5.3 (default-fancy) | ✅ | pure-Rust fancy-regex 백엔드 |
| reqwest 0.12 (rustls-tls) | ✅ | native-tls 불필요 |
| image 0.25 | ✅ | |
| pulldown-cmark 0.12 | ✅ | |
| clap 4.5 | ✅ | |
| regex 1.11 | ✅ | |
| unicode-width 0.1 | ✅ | |

---

## 빌드 방법

### 로컬 크로스 컴파일 (`scripts/build-win.sh`)

macOS 또는 Linux에서 Windows 실행 파일을 생성한다.

**사전 준비**

```bash
# macOS
brew install mingw-w64
rustup target add x86_64-pc-windows-gnu

# Ubuntu/Debian
sudo apt install gcc-mingw-w64-x86-64
rustup target add x86_64-pc-windows-gnu
```

**실행**

```bash
# debug 빌드 (빠른 확인용)
./scripts/build-win.sh

# release 빌드 (배포용, strip + LTO 적용)
./scripts/build-win.sh --release
```

출력 파일: `dist/windows/mdvi.exe`

---

### GitHub Actions (`.github/workflows/build-windows.yml`)

`develop` 브랜치, `feature/**` 브랜치 push 또는 PR 시 자동 실행.

| Job | 환경 | 타겟 | 용도 |
|-----|------|------|------|
| `build-windows` | `windows-latest` | `x86_64-pc-windows-msvc` | 배포용 기본 빌드 |
| `crossbuild-windows-gnu` | `ubuntu-latest` | `x86_64-pc-windows-gnu` | 크로스 컴파일 검증 |
| `release` | `ubuntu-latest` | — | `v*` 태그 시 GitHub Release에 `.exe` 자동 첨부 |

빌드 결과물(artifact)은 Actions 탭 → 해당 워크플로우 실행 → **Artifacts** 섹션에서 다운로드 가능.

**릴리즈 배포**

```bash
# 버전 태그를 push하면 GitHub Release에 .exe 자동 첨부
git tag v0.7.0
git push fork v0.7.0
```

---

## 진행 상황

- [x] 1. `file://` URI Windows 경로 처리 수정 — `%SystemDrive%` 기반, `#[cfg(windows)]` 빌드타임 분기 (2026-04-02)
- [x] 2. 이미지 프로토콜 자동감지 Windows fallback — `from_query_stdio()` skip, `#[cfg(windows)]` 빌드타임 분기 (2026-04-02)
- [x] 3. Auto → Halfblocks fallback 명시화 — Windows에서 `Auto` 시 `Halfblocks` 기본 적용 (2026-04-02)
- [x] 4. raw mode 에러 메시지 개선 — Windows 빌드 시 "Windows 10 1903 이상 필요" 안내 추가 (2026-04-02)
- [ ] 5. 클립보드 테스트 검증
- [x] 6. Windows 크로스 컴파일 빌드 테스트 (`x86_64-pc-windows-gnu`) — ✅ 성공 (2026-04-02)
- [x] 7. 빌드 스크립트 작성 — `scripts/build-win.sh` + `.github/workflows/build-windows.yml` (2026-04-03)
