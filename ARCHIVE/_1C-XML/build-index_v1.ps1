<#
  build-index_v1.ps1 — компактный индекс метаданных 1С из XML-выгрузки Конфигуратора.
  VERSION = 1.0

  Запуск (из корня проекта, Windows PowerShell 5.1+):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\engine\build-index_v1.ps1

  Что делает: читает <ProjectRoot>\config, пересоздаёт <ProjectRoot>\index целиком,
  кладёт правило для Roo в <ProjectRoot>\.roo\rules\1c-metadata-index.md (если не -NoRooRule).
  Выгрузку не меняет. Повторный запуск безопасен (индекс просто собирается заново).

  ВАЖНО: файл должен оставаться в UTF-8 с BOM, иначе Windows PowerShell 5.1 испортит кириллицу.
  Описание: engine\README.md (человеку), engine\AGENT.md (ИИ).
#>
param(
    [string]$ProjectRoot = '',
    [string]$ConfigPath  = '',
    [string]$OutPath     = '',
    [switch]$NoRooRule
)

$ErrorActionPreference = 'Stop'
$VERSION       = '1.0'
$RULE_TEMPLATE = 'roo-rule.md'   # шаблон правила лежит рядом со скриптом

if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
if (-not $ConfigPath)  { $ConfigPath  = Join-Path $ProjectRoot 'config' }
if (-not $OutPath)     { $OutPath     = Join-Path $ProjectRoot 'index' }

if (-not (Test-Path -LiteralPath (Join-Path $ConfigPath 'Configuration.xml'))) {
    throw "Не найдена выгрузка: нет файла $ConfigPath\Configuration.xml. Укажи -ConfigPath."
}
$ConfigPath  = (Resolve-Path -LiteralPath $ConfigPath).Path
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# ---------- справочники соответствий ----------

# Папка выгрузки -> вид объекта (как в языке запросов) и какие дочерние элементы читать
$Kinds = [ordered]@{
    'Catalogs'                    = @{ Ru='Справочник';              Child=@('Attribute','TabularSection') }
    'Documents'                   = @{ Ru='Документ';                Child=@('Attribute','TabularSection') }
    'DocumentJournals'            = @{ Ru='ЖурналДокументов';        Child=@('Column') }
    'Enums'                       = @{ Ru='Перечисление';            Child=@('EnumValue') }
    'ChartsOfCharacteristicTypes' = @{ Ru='ПланВидовХарактеристик';  Child=@('Attribute','TabularSection') }
    'ChartsOfAccounts'            = @{ Ru='ПланСчетов';              Child=@('Attribute','TabularSection','AccountingFlag','ExtDimensionAccountingFlag') }
    'ChartsOfCalculationTypes'    = @{ Ru='ПланВидовРасчета';        Child=@('Attribute','TabularSection') }
    'ExchangePlans'               = @{ Ru='ПланОбмена';              Child=@('Attribute','TabularSection') }
    'BusinessProcesses'           = @{ Ru='БизнесПроцесс';           Child=@('Attribute','TabularSection') }
    'Tasks'                       = @{ Ru='Задача';                  Child=@('Attribute','AddressingAttribute','TabularSection') }
    'InformationRegisters'        = @{ Ru='РегистрСведений';         Child=@('Dimension','Resource','Attribute') }
    'AccumulationRegisters'       = @{ Ru='РегистрНакопления';       Child=@('Dimension','Resource','Attribute') }
    'AccountingRegisters'         = @{ Ru='РегистрБухгалтерии';      Child=@('Dimension','Resource','Attribute') }
    'CalculationRegisters'        = @{ Ru='РегистрРасчета';          Child=@('Dimension','Resource','Attribute') }
    'Constants'                   = @{ Ru='Константа';               Child=@() }
    'DefinedTypes'                = @{ Ru='ОпределяемыйТип';         Child=@() }
    'CommonAttributes'            = @{ Ru='ОбщийРеквизит';           Child=@() }
}

# Ссылочные типы в описании типа (cfg:CatalogRef.X -> СправочникСсылка.X)
$RefMap = @{
    'CatalogRef'='СправочникСсылка'; 'DocumentRef'='ДокументСсылка'; 'EnumRef'='ПеречислениеСсылка'
    'ChartOfCharacteristicTypesRef'='ПланВидовХарактеристикСсылка'; 'ChartOfAccountsRef'='ПланСчетовСсылка'
    'ChartOfCalculationTypesRef'='ПланВидовРасчетаСсылка'; 'ExchangePlanRef'='ПланОбменаСсылка'
    'BusinessProcessRef'='БизнесПроцессСсылка'; 'TaskRef'='ЗадачаСсылка'
    'BusinessProcessRoutePointRef'='ТочкаМаршрутаБизнесПроцессаСсылка'
    'DefinedType'='ОпределяемыйТип'; 'Characteristic'='Характеристика'; 'AnyRef'='ЛюбаяСсылка'
}

# Имена объектов в свойствах (Catalog.X -> Справочник.X): владельцы, движения документов
$MdMap = @{
    'Catalog'='Справочник'; 'Document'='Документ'; 'Enum'='Перечисление'
    'ChartOfCharacteristicTypes'='ПланВидовХарактеристик'; 'ChartOfAccounts'='ПланСчетов'
    'ChartOfCalculationTypes'='ПланВидовРасчета'; 'ExchangePlan'='ПланОбмена'
    'BusinessProcess'='БизнесПроцесс'; 'Task'='Задача'
    'InformationRegister'='РегистрСведений'; 'AccumulationRegister'='РегистрНакопления'
    'AccountingRegister'='РегистрБухгалтерии'; 'CalculationRegister'='РегистрРасчета'
}

$Section = @{ # заголовок раздела в карточке, вид поля в _fields.tsv
    'Attribute'                  = @('Реквизиты','Реквизит')
    'AddressingAttribute'        = @('Реквизиты адресации','РеквизитАдресации')
    'Dimension'                  = @('Измерения','Измерение')
    'Resource'                   = @('Ресурсы','Ресурс')
    'EnumValue'                  = @('Значения','Значение')
    'Column'                     = @('Графы','Графа')
    'AccountingFlag'             = @('Признаки учета','ПризнакУчета')
    'ExtDimensionAccountingFlag' = @('Признаки учета субконто','ПризнакУчетаСубконто')
}

# ---------- помощники ----------

# 'Properties/Name' -> XPath без пространств имён
function Q([string]$path) { ($path -split '/' | ForEach-Object { "*[local-name()='$_']" }) -join '/' }

function T($node, [string]$path) {
    if (-not $node) { return '' }
    $x = $node.SelectSingleNode((Q $path))
    if ($x) { return $x.InnerText.Trim() } else { return '' }
}

function Get-Syn($props) {
    if (-not $props) { return '' }
    $items = $props.SelectNodes((Q 'Synonym/item'))
    foreach ($i in $items) { if ((T $i 'lang') -eq 'ru') { return (T $i 'content') } }
    if ($items.Count -gt 0) { return (T $items[0] 'content') }
    return ''
}

function Md-Ru([string]$s) {
    $parts = $s.Split('.', 2)
    if ($parts.Count -eq 2 -and $MdMap.ContainsKey($parts[0])) { return "$($MdMap[$parts[0]]).$($parts[1])" }
    return $s
}

function Get-Items($props, [string]$name) {   # список xr:Item внутри свойства (Owners, RegisterRecords)
    $res = @()
    if (-not $props) { return $res }
    foreach ($i in $props.SelectNodes((Q "$name/Item"))) { $res += (Md-Ru $i.InnerText.Trim()) }
    return $res
}

function Convert-TypeName([string]$raw, $typeNode) {
    $t = $raw -replace '^[^:]+:', ''
    switch -Exact ($t) {
        'string' {
            $len = T $typeNode 'StringQualifiers/Length'
            if (-not $len -or $len -eq '0') { return 'Строка(неогр)' } else { return "Строка($len)" }
        }
        'decimal' {
            $d = T $typeNode 'NumberQualifiers/Digits'; $f = T $typeNode 'NumberQualifiers/FractionDigits'
            if (-not $f) { $f = '0' }
            return "Число($d,$f)"
        }
        'boolean'        { return 'Булево' }
        'dateTime' {
            switch (T $typeNode 'DateQualifiers/DateFractions') {
                'Date' { return 'Дата' }
                'Time' { return 'Время' }
                default { return 'ДатаВремя' }
            }
        }
        'ValueStorage'   { return 'ХранилищеЗначения' }
        'UUID'           { return 'УникальныйИдентификатор' }
        'base64Binary'   { return 'ДвоичныеДанные' }
        'StandardPeriod' { return 'СтандартныйПериод' }
    }
    $parts = $t.Split('.', 2)
    if ($RefMap.ContainsKey($parts[0])) {
        if ($parts.Count -eq 2) { return "$($RefMap[$parts[0]]).$($parts[1])" } else { return $RefMap[$parts[0]] }
    }
    return $raw   # незнакомый тип оставляем как есть
}

function Convert-Type($typeNode) {
    if (-not $typeNode) { return '' }
    $parts = @()
    foreach ($c in $typeNode.ChildNodes) {
        if ($c.NodeType -ne 'Element') { continue }
        if ($c.LocalName -eq 'Type' -or $c.LocalName -eq 'TypeSet') {
            $parts += (Convert-TypeName $c.InnerText.Trim() $typeNode)
        }
    }
    return ($parts -join ' | ')
}

function Get-Fields($node, [string[]]$kinds) {
    $res = New-Object System.Collections.Generic.List[object]
    $co = $node.SelectSingleNode((Q 'ChildObjects'))
    if (-not $co) { return ,$res }
    foreach ($c in $co.ChildNodes) {
        if ($c.NodeType -ne 'Element' -or ($kinds -notcontains $c.LocalName)) { continue }
        $p = $c.SelectSingleNode((Q 'Properties'))
        $res.Add([pscustomobject]@{
            Kind = $c.LocalName
            Name = (T $p 'Name')
            Syn  = (Get-Syn $p)
            Type = (Convert-Type ($p.SelectSingleNode((Q 'Type'))))
            Node = $c
        })
    }
    return ,$res
}

function Clean([string]$s) { return ($s -replace '[\t\r\n]+', ' ').Trim() }

function Fmt-Field($f) {
    $s = "- $($f.Name)"
    if ($f.Type) { $s += ": $($f.Type)" }
    if ($f.Syn -and (($f.Syn -replace '\s', '') -ne $f.Name)) { $s += " — «$(Clean $f.Syn)»" }
    return $s
}

function Get-Std([string]$folder, $p) {   # стандартные поля для запросов + доп. строки карточки
    $std = @(); $extra = @()
    switch ($folder) {
        'Catalogs' {
            $std += 'Ссылка'
            if ((T $p 'CodeLength') -ne '0') { $std += 'Код' }
            if ((T $p 'DescriptionLength') -ne '0') { $std += 'Наименование' }
            if ((T $p 'Hierarchical') -eq 'true') {
                $std += 'Родитель'
                if ((T $p 'HierarchyType') -ne 'HierarchyOfItems') { $std += 'ЭтоГруппа' }
            }
            $owners = Get-Items $p 'Owners'
            if ($owners.Count -gt 0) { $std += 'Владелец'; $extra += "Владельцы: $($owners -join ', ')" }
            $std += 'ПометкаУдаления', 'Предопределенный'
        }
        'Documents' {
            $std += 'Ссылка', 'Номер', 'Дата', 'Проведен', 'ПометкаУдаления'
            $rr = Get-Items $p 'RegisterRecords'
            if ($rr.Count -gt 0) { $extra += "Движения: $($rr -join ', ')" }
        }
        'Enums'                       { $std += 'Ссылка', 'Порядок' }
        'ChartsOfCharacteristicTypes' { $std += 'Ссылка', 'Код', 'Наименование', 'ТипЗначения', 'Родитель', 'ПометкаУдаления', 'Предопределенный' }
        'ChartsOfAccounts'            { $std += 'Ссылка', 'Код', 'Наименование', 'Родитель', 'Вид', 'Забалансовый', 'Порядок', 'ПометкаУдаления' }
        'ChartsOfCalculationTypes'    { $std += 'Ссылка', 'Код', 'Наименование', 'ПометкаУдаления', 'Предопределенный' }
        'ExchangePlans'               { $std += 'Ссылка', 'Код', 'Наименование', 'НомерОтправленного', 'НомерПринятого', 'ЭтотУзел', 'ПометкаУдаления' }
        'BusinessProcesses'           { $std += 'Ссылка', 'Номер', 'Дата', 'Стартован', 'Завершен', 'ВедущаяЗадача', 'ПометкаУдаления' }
        'Tasks'                       { $std += 'Ссылка', 'Номер', 'Дата', 'Наименование', 'Выполнена', 'БизнесПроцесс', 'ТочкаМаршрута', 'ПометкаУдаления' }
        'DocumentJournals'            { $std += 'Ссылка', 'Тип', 'Номер', 'Дата', 'Проведен', 'ПометкаУдаления' }
        'InformationRegisters' {
            $periodic = (T $p 'InformationRegisterPeriodicity')
            if ($periodic -and $periodic -ne 'Nonperiodical') { $std += 'Период'; $extra += 'Виртуальные таблицы: СрезПоследних, СрезПервых' }
            if ((T $p 'WriteMode') -eq 'RecorderSubordinate') { $std += 'Регистратор', 'НомерСтроки', 'Активность' }
        }
        'AccumulationRegisters' {
            $std += 'Период', 'Регистратор', 'НомерСтроки', 'Активность'
            if ((T $p 'RegisterType') -eq 'Turnovers') { $extra += 'Виртуальные таблицы: Обороты' }
            else { $std += 'ВидДвижения'; $extra += 'Виртуальные таблицы: Остатки, Обороты, ОстаткиИОбороты' }
        }
        'AccountingRegisters'  { $std += 'Период', 'Регистратор', 'НомерСтроки', 'Активность'; $extra += 'Виртуальные таблицы: Остатки, Обороты, ОстаткиИОбороты, ДвиженияССубконто' }
        'CalculationRegisters' { $std += 'Регистратор', 'НомерСтроки', 'Активность', 'ВидРасчета', 'ПериодРегистрации' }
    }
    return @{ Std = ($std -join ', '); Extra = $extra }
}

# ---------- подготовка папки индекса ----------

if (Test-Path -LiteralPath $OutPath) {
    $existing = @(Get-ChildItem -LiteralPath $OutPath -Force)
    if ($existing.Count -gt 0 -and -not (Test-Path -LiteralPath (Join-Path $OutPath '_build.txt'))) {
        throw "Папка $OutPath не пуста и не похожа на индекс (нет _build.txt). Укажи другую -OutPath."
    }
    Remove-Item -LiteralPath $OutPath -Recurse -Force
}
$CardsPath = Join-Path $OutPath 'cards'
New-Item -ItemType Directory -Path $CardsPath -Force | Out-Null
$OutPath = (Resolve-Path -LiteralPath $OutPath).Path

# ---------- обход выгрузки ----------

$objects = New-Object System.Collections.Generic.List[string]
$fields  = New-Object System.Collections.Generic.List[string]
$errors  = New-Object System.Collections.Generic.List[string]
$stats   = [ordered]@{}
$objects.Add("Вид`tИмя`tСиноним`tТаблицаЗапроса`tПолей`tКарточка")
$fields.Add("Таблица`tПоле`tТип`tСиноним`tВидПоля")

foreach ($folder in $Kinds.Keys) {
    $dir = Join-Path $ConfigPath $folder
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $ru    = $Kinds[$folder].Ru
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File)
    $ok = 0

    foreach ($file in $files) {
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml([System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8))
            $obj   = $xml.DocumentElement.SelectSingleNode('*')
            $props = $obj.SelectSingleNode((Q 'Properties'))
            $name  = T $props 'Name'
            $syn   = Clean (Get-Syn $props)
            $full  = "$ru.$name"
            $table = if ($folder -in @('DefinedTypes', 'CommonAttributes')) { '—' } else { $full }

            $card = New-Object System.Text.StringBuilder
            [void]$card.AppendLine("# $full — $syn")
            [void]$card.AppendLine("Таблица запроса: $table")
            $cmt = Clean (T $props 'Comment')
            if ($cmt) { [void]$card.AppendLine("Комментарий: $cmt") }

            $count = 0
            if ($folder -in @('Constants', 'DefinedTypes', 'CommonAttributes')) {
                $type = Convert-Type ($props.SelectSingleNode((Q 'Type')))
                [void]$card.AppendLine("Тип: $type")
                if ($folder -eq 'CommonAttributes') { [void]$card.AppendLine('Общий реквизит: доступен как реквизит объектов, входящих в его состав (состав см. в выгрузке).') }
                $fields.Add("$full`tЗначение`t$type`t$syn`t$ru")
                $count = 1
            } else {
                $s = Get-Std $folder $props
                if ($s.Std) { [void]$card.AppendLine("Стандартные поля: $($s.Std)") }
                foreach ($e in $s.Extra) { [void]$card.AppendLine($e) }

                $all = Get-Fields $obj $Kinds[$folder].Child
                foreach ($kind in $Kinds[$folder].Child) {
                    if ($kind -eq 'TabularSection') { continue }
                    $part = @($all | Where-Object { $_.Kind -eq $kind })
                    if ($part.Count -eq 0) { continue }
                    [void]$card.AppendLine('')
                    [void]$card.AppendLine("## $($Section[$kind][0])")
                    foreach ($f in $part) {
                        [void]$card.AppendLine((Fmt-Field $f))
                        $fields.Add("$table`t$($f.Name)`t$($f.Type)`t$(Clean $f.Syn)`t$($Section[$kind][1])")
                        $count++
                    }
                }
                foreach ($ts in @($all | Where-Object { $_.Kind -eq 'TabularSection' })) {
                    $tsTable = "$full.$($ts.Name)"
                    [void]$card.AppendLine('')
                    $tsTitle = "## ТЧ $($ts.Name)"
                    if ($ts.Syn -and (($ts.Syn -replace '\s', '') -ne $ts.Name)) { $tsTitle += " — «$(Clean $ts.Syn)»" }
                    [void]$card.AppendLine($tsTitle)
                    [void]$card.AppendLine("Таблица запроса: $tsTable (стандартные: Ссылка, НомерСтроки)")
                    foreach ($f in (Get-Fields $ts.Node @('Attribute'))) {
                        [void]$card.AppendLine((Fmt-Field $f))
                        $fields.Add("$tsTable`t$($f.Name)`t$($f.Type)`t$(Clean $f.Syn)`tРеквизитТЧ")
                        $count++
                    }
                }
            }

            $cardName = "$full.md"
            [System.IO.File]::WriteAllText((Join-Path $CardsPath $cardName), $card.ToString(), $Utf8)
            $objects.Add("$ru`t$name`t$syn`t$table`t$count`tcards/$cardName")
            $ok++
        } catch {
            $errors.Add("$folder\$($file.Name): $($_.Exception.Message)")
        }
    }
    $stats[$ru] = "$ok из $($files.Count)"
}

# ---------- итоговые файлы ----------

[System.IO.File]::WriteAllText((Join-Path $OutPath '_objects.tsv'), ($objects -join "`r`n") + "`r`n", $Utf8)
[System.IO.File]::WriteAllText((Join-Path $OutPath '_fields.tsv'),  ($fields  -join "`r`n") + "`r`n", $Utf8)

$cfgXml = New-Object System.Xml.XmlDocument
$cfgXml.LoadXml([System.IO.File]::ReadAllText((Join-Path $ConfigPath 'Configuration.xml'), [System.Text.Encoding]::UTF8))
$cfgProps = $cfgXml.DocumentElement.SelectSingleNode('*').SelectSingleNode((Q 'Properties'))

$skipped = @(Get-ChildItem -LiteralPath $ConfigPath -Directory |
    Where-Object { -not $Kinds.Contains($_.Name) -and $_.Name -ne 'Ext' } |
    ForEach-Object { $_.Name })

$build = New-Object System.Text.StringBuilder
[void]$build.AppendLine("Индекс метаданных 1С (build-index_v$VERSION)")
[void]$build.AppendLine("Собран: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$build.AppendLine("Выгрузка: $ConfigPath")
[void]$build.AppendLine("Конфигурация: $(T $cfgProps 'Name') — $(Get-Syn $cfgProps), версия $(T $cfgProps 'Version')")
[void]$build.AppendLine("Объектов: $($objects.Count - 1), полей: $($fields.Count - 1)")
[void]$build.AppendLine('')
[void]$build.AppendLine('Обработано по видам (успешно из файлов):')
foreach ($k in $stats.Keys) { [void]$build.AppendLine("  $k : $($stats[$k])") }
[void]$build.AppendLine('')
[void]$build.AppendLine("Не индексируются (формы, модули, роли и пр. — смотреть в выгрузке): $($skipped -join ', ')")
[void]$build.AppendLine('')
[void]$build.AppendLine("Ошибок: $($errors.Count)")
foreach ($e in $errors) { [void]$build.AppendLine("  $e") }
[System.IO.File]::WriteAllText((Join-Path $OutPath '_build.txt'), $build.ToString(), $Utf8)

# ---------- правило для Roo ----------

if (-not $NoRooRule) {
    $tpl = Join-Path $PSScriptRoot $RULE_TEMPLATE
    if (Test-Path -LiteralPath $tpl) {
        $rel = $OutPath.Substring($ProjectRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        if (-not $rel) { $rel = '.' }
        $ruleDir = Join-Path $ProjectRoot '.roo\rules'
        New-Item -ItemType Directory -Path $ruleDir -Force | Out-Null
        $rule = [System.IO.File]::ReadAllText($tpl, [System.Text.Encoding]::UTF8).Replace('{{INDEX}}', $rel)
        [System.IO.File]::WriteAllText((Join-Path $ruleDir '1c-metadata-index.md'), $rule, $Utf8)
    } else {
        Write-Warning "Нет шаблона правила $tpl — правило для Roo не создано."
    }
}

Write-Host ($build.ToString())
if ($errors.Count -gt 0) { Write-Warning "Есть ошибки разбора: $($errors.Count) (см. _build.txt)"; exit 1 }
