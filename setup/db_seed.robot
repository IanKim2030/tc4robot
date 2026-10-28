*** Settings ***
Documentation
...    실행 전 DB 설정 정보 확인 → 없으면 INSERT (config/db_seed/<env>.sql)
...
...    시드 파일은 환경별이다. run_tests.sh 가 환경 인자로 골라 ${DB_SEED_FILE} 로
...    넘긴다(없음/IP → dev.sql, stg → stg.sql). 파일이 없으면 접속 없이 건너뛴다.
...    직접 돌릴 때: python -m robot --variable DB_SEED_FILE:config/db_seed/stg.sql
...    --variablefile config/env/stg.py setup/db_seed.robot
...
...    run_tests.sh 가 **본 실행 전에 한 번** 별도 robot 실행으로 부른다. tests/ 밖에
...    두어 `all` 이나 태그 실행에 섞이지 않는다. 별도 실행이라도 run_tests.sh 가
...    본 실행과 같은 --variablefile / --variable 을 넘기므로 접속 문자열 우선순위
...    (환경변수 PG_PDB_CONNSTR > --variable > config/env/<env>.py > variables.robot)는
...    본 실행과 같다.
...
...    블록마다 확인 SELECT(1행 1열 정수)가 0 이면 INSERT 하고, 다시 세어 1 이상인지
...    본다. 1 이상이면 그 블록의 UPDATE 를 실행한다(없으면 건너뛴다 — 멱등).
...    실행한 INSERT/UPDATE 는 문장마다 콘솔·log.html 에 남는다.
...    블록이 하나도 없으면 DB 에 접속하지 않는다.
...    ${PDB_CONNSTR_2} 가 있으면 두 번째 DB 에도 같은 일을 한다.
...
...    ★ `python -m robot tests/...` 로 직접 돌리면 이 단계는 돌지 않는다.
...      필요하면 먼저 `python -m robot setup/db_seed.robot` 를 부를 것.
...
...    생략: bash run_tests.sh <대상> --no-db-seed
...    확인만: bash run_tests.sh <대상> --db-seed-check

Resource    ../resources/variables.robot
Library     ../resources/CdsDbHelper.py    WITH NAME    SeedDb
Library     ../resources/DbSeedHelper.py    WITH NAME    Seed
Library     OperatingSystem

Suite Teardown    Close Seed DB Connections

*** Variables ***
${SEED_DB_CONN}      ${None}
${SEED_DB_CONN_2}    ${None}

*** Test Cases ***
DB 설정 정보 확인 및 적재
    [Documentation]    ${DB_SEED_FILE} 의 블록마다 확인 SELECT → 0건이면 INSERT(재확인) / 1건 이상이면 UPDATE.
    ${exists}=    Run Keyword And Return Status    File Should Exist    ${DB_SEED_FILE}
    IF    not ${exists}
        Log    [Seed] 이 환경의 시드 파일이 없습니다 — DB 접속 없이 지나갑니다 (${DB_SEED_FILE})    console=True
        Pass Execution    시드 파일 없음
    END
    ${blocks}=    Seed.Load Seed Blocks    ${DB_SEED_FILE}
    ${count}=     Get Length    ${blocks}
    IF    ${count} == 0
        Log    [Seed] 시드 블록 없음 — DB 접속 없이 지나갑니다 (${DB_SEED_FILE})    console=True
        Pass Execution    시드 블록 없음
    END
    Log    [Seed] 시드 블록 ${count}건 (${DB_SEED_FILE}, 확인만=${DB_SEED_CHECK_ONLY})    console=True
    Open Seed DB Connections
    Apply Seed Blocks    ${SEED_DB_CONN}    DB1    ${blocks}
    IF    $SEED_DB_CONN_2 is not None
        Apply Seed Blocks    ${SEED_DB_CONN_2}    DB2    ${blocks}
    END

*** Keywords ***
Open Seed DB Connections
    [Documentation]
    ...    PDB 에 접속한다. 접속 문자열은 인자로 넘기지 않는다 — 비밀번호가 log.html 에
    ...    남기 때문이다(`Ensure CDS DB Connection` 과 같은 이유). 로그에는 마스킹된
    ...    문자열만 남는다. ${PDB_CONNSTR_2} 가 있으면 두 번째 DB 에도 붙는다.
    ${shown}=    SeedDb.Masked Conn Str
    Log    [Seed] PDB 접속 시도 — ${shown}    console=True
    ${conn}=    SeedDb.Db Connect    timeout=${DB_SEED_TIMEOUT}    autocommit=${FALSE}
    Set Suite Variable    ${SEED_DB_CONN}    ${conn}
    ${has_2nd}=    SeedDb.Has Second Db
    IF    ${has_2nd}
        ${shown_2}=    SeedDb.Masked Conn Str    which=${2}
        Log    [Seed] 두 번째 PDB 접속 시도 — ${shown_2}    console=True
        ${conn_2}=    SeedDb.Db Connect    timeout=${DB_SEED_TIMEOUT}    autocommit=${FALSE}    which=${2}
        Set Suite Variable    ${SEED_DB_CONN_2}    ${conn_2}
    END

Apply Seed Blocks
    [Documentation]
    ...    한 DB 에 블록 전체를 적용한다. 확인 SELECT 결과로 갈린다.
    ...      0건      → INSERT 실행 → 같은 SELECT 로 다시 세어 1건 이상인지 확인
    ...      1건 이상 → UPDATE 실행 (UPDATE 문이 없으면 "SELECT" 로그만 남기고 건너뜀)
    ...    실행한 INSERT/UPDATE 는 문장마다 대상 표·영향 행 수를 콘솔에, 전체 SQL 을
    ...    log.html 에 남긴다. 끝에 DB 별 요약(SELECT/INSERT/UPDATE 건수)을 찍는다.
    ...    확인만 모드에서는 아무것도 실행하지 않는다 — INSERT 대상은 WARN, UPDATE
    ...    대상은 콘솔 로그로만 남기고 실패하지 않는다(본 실행은 진행된다).
    [Arguments]    ${conn}    ${db}    ${blocks}
    ${n_keep}=    Set Variable    ${0}
    ${n_ins}=     Set Variable    ${0}
    ${n_upd}=     Set Variable    ${0}
    FOR    ${b}    IN    @{blocks}
        ${existing}=    SeedDb.Db Count    ${conn}    ${b}[check]
        IF    ${existing} > 0
            IF    not $b['updates']
                Log    [Seed] SELECT (${db}) — ${b}[name] — ${existing}건    console=True
                ${n_keep}=    Evaluate    ${n_keep} + 1
                CONTINUE
            END
            IF    ${DB_SEED_CHECK_ONLY}
                Log    [Seed] SELECT (${db}) — ${b}[name] — ${existing}건 — 확인만 모드라 UPDATE 하지 않았습니다    console=True
                CONTINUE
            END
            FOR    ${sql}    IN    @{b}[updates]
                Execute Seed Statement    ${conn}    ${db}    ${b}[name]    UPDATE    ${sql}
            END
            ${n_upd}=    Evaluate    ${n_upd} + 1
            CONTINUE
        END
        IF    not $b['inserts']
            Log    [Seed] 없음 (${db}) — ${b}[name] — INSERT 문이 없는 블록이라 건너뜁니다    console=True
            CONTINUE
        END
        IF    ${DB_SEED_CHECK_ONLY}
            Log    [Seed] 없음 (${db}) — ${b}[name] — 확인만 모드라 넣지 않았습니다    level=WARN
            CONTINUE
        END
        FOR    ${sql}    IN    @{b}[inserts]
            Execute Seed Statement    ${conn}    ${db}    ${b}[name]    INSERT    ${sql}
        END
        ${after}=    SeedDb.Db Count    ${conn}    ${b}[check]
        Should Be True    ${after} >= 1
        ...    msg=[Seed] ${db} — ${b}[name] INSERT 후 확인 SELECT 기대=1건 이상, 실제=${after} (확인 SELECT 와 INSERT 가 같은 행을 가리키는지 볼 것)
        Log    [Seed] INSERT 확인 (${db}) — ${b}[name] — 확인 SELECT ${after}건    console=True
        ${n_ins}=    Evaluate    ${n_ins} + 1
    END
    Log    [Seed] 요약 (${db}) — SELECT ${n_keep} / INSERT ${n_ins} / UPDATE ${n_upd} (블록 기준)    console=True

Execute Seed Statement
    [Documentation]
    ...    INSERT/UPDATE 한 문장을 실행(commit)하고 로그를 남긴다.
    ...      콘솔    : 대상 표와 영향 행 수 한 줄
    ...      log.html : 전체 SQL
    ...    UPDATE 가 0행이면 WARN 이다(실패는 아니다) — 드라이버가 영향 행 수를 안
    ...    주는 경우도 0 으로 보이기 때문이다. 확인 SELECT 와 UPDATE 의 WHERE 가 같은
    ...    행을 가리키는지 볼 것.
    [Arguments]    ${conn}    ${db}    ${name}    ${kind}    ${sql}
    ${target}=    Seed.Describe Statement    ${sql}
    ${rows}=      SeedDb.Db Execute    ${conn}    ${sql}
    Log    [Seed] ${kind} (${db}) — ${name} — ${target} — ${rows}행    console=True
    Log    [Seed] ${kind} 실행 SQL (${db}, ${name}):\n${sql}
    IF    '${kind}' == 'UPDATE' and ${rows} == 0
        Log    [Seed] UPDATE 영향 행 0 (${db}) — ${name} — ${target}. 확인 SELECT 와 WHERE 가 같은 행을 가리키는지 볼 것    level=WARN
    END

Close Seed DB Connections
    SeedDb.Db Close    ${SEED_DB_CONN}
    SeedDb.Db Close    ${SEED_DB_CONN_2}
