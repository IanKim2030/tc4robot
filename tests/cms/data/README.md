# CMS 시험 샘플 파일

`<SERVICE_CODE>.dat` 이름으로 실제 데이터 파일을 둔다(예: `TRAP_LTE_EQP_INFO.dat`, `TRAP_5G_EQP_INFO.dat`).

- `Send CMS NTI` 는 이 파일이 있으면 내용을 그대로 SFTP 서버에 올린다.
  파일명의 크기 자리(`<이름>_<일시>_<크기>.dat`)와 T_CMSWEB_ZONE FILESIZE 기대값도 이 파일의 실제 크기를 쓴다.
- 파일이 없는 서비스코드는 `CMS_FILE_BYTES`(기본 128) 바이트 시험 데이터를 만든다.
- `.gitattributes` 에서 binary 로 지정했다 — 줄바꿈이 바뀌면 크기가 달라진다.
- FTP(TYPE A) 모드에서는 LF 가 CRLF 로 바뀌어 크기가 달라질 수 있다. SFTP 모드는 그대로다.
