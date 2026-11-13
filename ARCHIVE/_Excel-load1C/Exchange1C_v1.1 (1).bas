Attribute VB_Name = "Exchange1C"
'==============================================================================
' Модуль Exchange1C, версия 1.1
' Универсальная выгрузка результата запроса 1С в лист Excel через COM-соединение.
' Все настройки - на листе «Параметры» (именованные диапазоны Обмен_*).
' Работает с книгой формата Exchange1C_v1.x (см. SETTINGS_FORMAT_MAJOR).
' Запуск: Alt+F8 -> ВыгрузитьИз1С
'
' 1.1: пароль через InputBox, если в книге пустой; тип «СправочникПоКоду»;
'      строка параметра с «//» в имени пропускается; настройка «Заголовки» (необязательная)
'==============================================================================
Option Explicit

Public Const MODULE_VERSION As String = "1.1"
' Мажор формата листа настроек, с которым совместим модуль
Private Const SETTINGS_FORMAT_MAJOR As Long = 1

' Именованные диапазоны листа настроек
Private Const NM_QUERY As String = "Обмен_Запрос"
Private Const NM_SERVER As String = "Обмен_Сервер"
Private Const NM_BASE As String = "Обмен_База"
Private Const NM_USER As String = "Обмен_Пользователь"
Private Const NM_PASSWORD As String = "Обмен_Пароль"
Private Const NM_CONNECTOR As String = "Обмен_Коннектор"
Private Const NM_SHEET As String = "Обмен_Лист"
Private Const NM_COL_OFFSET As String = "Обмен_СмещКолонок"
Private Const NM_ROW_OFFSET As String = "Обмен_СмещСтрок"
Private Const NM_MODE As String = "Обмен_Режим"
Private Const NM_FORMAT As String = "Обмен_ВерсияФормата"
Private Const NM_HEADERS As String = "Обмен_Заголовки"        ' необязательная (с 1.1), по умолчанию «Да»
Private Const NM_PARAMS As String = "Обмен_Параметры"      ' ячейка заголовка таблицы параметров
' Скрытое имя: область прошлой выгрузки (создаётся модулем)
Private Const NM_LAST_OUTPUT As String = "Обмен_ПоследняяВыгрузка"

Private Const DEFAULT_CONNECTOR As String = "V83.COMConnector"
Private Const ERR_USER As Long = vbObjectError + 513
Private Const MAX_CELL_TEXT As Long = 32767

' Пароль, введённый через InputBox, - живёт до закрытия Excel, сбрасывается при неудачном подключении
Private cachedPassword As String
Private hasCachedPassword As Boolean

'------------------------------------------------------------------------------
' Точка входа
'------------------------------------------------------------------------------
Public Sub ВыгрузитьИз1С()
    Dim conn As Object
    Dim qResult As Object
    Dim rowsCount As Long, colsCount As Long
    Dim startTime As Double
    Dim prevCalc As Long
    Dim errMsg As String

    startTime = Timer
    prevCalc = Application.Calculation
    On Error GoTo ErrorHandler

    CheckSettingsFormat

    Application.StatusBar = "Обмен с 1С: подключение..."
    Set conn = ConnectToBase()

    Application.StatusBar = "Обмен с 1С: выполнение запроса..."
    Set qResult = ExecuteQuery(conn)

    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    rowsCount = ExportData(qResult, conn, colsCount)

    RestoreApp prevCalc
    MsgBox "Готово. Записей: " & rowsCount & ", колонок: " & colsCount & vbCrLf & _
           "Время выполнения: " & Format(Timer - startTime, "0.00") & " сек.", _
           vbInformation, "Обмен с 1С"
    GoTo CleanUp

ErrorHandler:
    errMsg = Err.Description          ' запомнить до RestoreApp: On Error внутри него сбросит Err
    RestoreApp prevCalc
    MsgBox "Ошибка: " & errMsg, vbCritical, "Обмен с 1С"
CleanUp:
    Set qResult = Nothing
    Set conn = Nothing
End Sub

'------------------------------------------------------------------------------
' Настройки
'------------------------------------------------------------------------------
Private Function Setting(ByVal rangeName As String) As Range
    Dim rng As Range
    On Error Resume Next
    Set rng = ThisWorkbook.Names(rangeName).RefersToRange
    On Error GoTo 0
    If rng Is Nothing Then RaiseUser "Не найден именованный диапазон «" & rangeName & _
                                     "». Книга не соответствует формату настроек v" & SETTINGS_FORMAT_MAJOR & "."
    Set Setting = rng.Cells(1, 1)
End Function

Private Function SettingText(ByVal rangeName As String) As String
    SettingText = Trim$(CStr(Setting(rangeName).Value))
End Function

' Необязательная настройка: нет именованного диапазона или ячейка пустая - значение по умолчанию
Private Function OptionalSettingText(ByVal rangeName As String, ByVal defaultValue As String) As String
    Dim rng As Range
    On Error Resume Next
    Set rng = ThisWorkbook.Names(rangeName).RefersToRange
    On Error GoTo 0
    If Not rng Is Nothing Then OptionalSettingText = Trim$(CStr(rng.Cells(1, 1).Value))
    If OptionalSettingText = "" Then OptionalSettingText = defaultValue
End Function

Private Function SettingLong(ByVal rangeName As String) As Long
    Dim v As Variant
    v = Setting(rangeName).Value
    If Trim$(CStr(v)) = "" Then Exit Function
    If Not IsNumeric(v) Then RaiseUser "Настройка «" & rangeName & "»: ожидается число, указано «" & v & "»."
    If CLng(v) < 0 Then RaiseUser "Настройка «" & rangeName & "» не может быть отрицательной."
    SettingLong = CLng(v)
End Function

' Контроль соответствия версии листа настроек и модуля
Private Sub CheckSettingsFormat()
    Dim v As Variant
    v = Setting(NM_FORMAT).Value
    If Not IsNumeric(v) Then RaiseUser "Не указана версия формата листа настроек (" & NM_FORMAT & ")."
    If Int(CDbl(v)) <> SETTINGS_FORMAT_MAJOR Then
        RaiseUser "Формат листа настроек v" & v & " несовместим с модулем Exchange1C " & MODULE_VERSION & _
                  " (нужен формат v" & SETTINGS_FORMAT_MAJOR & ".x). Обновите модуль или книгу."
    End If
End Sub

'------------------------------------------------------------------------------
' Подключение
'------------------------------------------------------------------------------
Private Function ConnectToBase() As Object
    Dim connector As Object
    Dim progId As String, serverName As String, baseName As String
    Dim userName As String, password As String, connStr As String

    serverName = SettingText(NM_SERVER)
    baseName = SettingText(NM_BASE)
    userName = SettingText(NM_USER)
    password = CStr(Setting(NM_PASSWORD).Value)        ' пароль без Trim
    progId = SettingText(NM_CONNECTOR)
    If progId = "" Then progId = DEFAULT_CONNECTOR
    If serverName = "" Or baseName = "" Then RaiseUser "Не заданы сервер 1С и/или имя информационной базы."
    If userName <> "" And password = "" Then password = AskPassword(userName)

    connStr = "Srvr=" & Quote1C(serverName) & ";Ref=" & Quote1C(baseName) & ";"
    If userName <> "" Then connStr = connStr & "Usr=" & Quote1C(userName) & ";Pwd=" & Quote1C(password) & ";"

    On Error GoTo NoConnector
    Set connector = CreateObject(progId)
    On Error GoTo NoConnect
    Set ConnectToBase = connector.Connect(connStr)
    On Error GoTo 0
    If ConnectToBase Is Nothing Then RaiseUser "Не удалось подключиться к базе " & serverName & "\" & baseName & "."
    Exit Function

NoConnector:
    RaiseUser "Не удалось создать COM-объект «" & progId & "»: " & Err.Description & vbCrLf & _
              "Проверьте, что COM-коннектор 1С зарегистрирован и разрядность Excel совпадает с разрядностью 1С."
NoConnect:
    hasCachedPassword = False             ' возможно, пароль введён неверно - спросить заново
    cachedPassword = ""
    RaiseUser "Не удалось подключиться к базе " & serverName & "\" & baseName & ": " & Err.Description
End Function

' Пароль не хранится в книге: спросить один раз за сеанс Excel. Отмена - прервать выгрузку
Private Function AskPassword(ByVal userName As String) As String
    Dim answer As String
    If Not hasCachedPassword Then
        answer = InputBox("Пароль 1С для пользователя «" & userName & "»:" & vbCrLf & _
                          "(запоминается до закрытия Excel; пустой - если пароля нет)", "Обмен с 1С")
        If StrPtr(answer) = 0 Then RaiseUser "Выгрузка отменена: пароль не введён."
        cachedPassword = answer
        hasCachedPassword = True
    End If
    AskPassword = cachedPassword
End Function

Private Function Quote1C(ByVal s As String) As String
    Quote1C = """" & Replace(s, """", """""") & """"
End Function

'------------------------------------------------------------------------------
' Запрос и параметры
'------------------------------------------------------------------------------
Private Function ExecuteQuery(conn As Object) As Object
    Dim q As Object
    Dim queryText As String

    queryText = CStr(Setting(NM_QUERY).Value)
    If Trim$(queryText) = "" Then RaiseUser "Не задан текст запроса."

    Set q = conn.NewObject("Запрос")
    q.Text = queryText
    SetQueryParameters conn, q

    On Error GoTo QueryFailed
    Set ExecuteQuery = q.Execute()
    Exit Function

QueryFailed:
    RaiseUser "Ошибка выполнения запроса: " & Err.Description
End Function

' Таблица параметров: строки под заголовком до первой пустой ячейки в колонке «Имя».
' Имя, начинающееся с «//», - строка отключена и пропускается
Private Sub SetQueryParameters(conn As Object, q As Object)
    Dim cell As Range
    Dim paramName As String
    Set cell = Setting(NM_PARAMS).Offset(1, 0)
    Do While Trim$(CStr(cell.Value)) <> ""
        paramName = Trim$(CStr(cell.Value))
        If Left$(paramName, 2) <> "//" Then
            SetOneParameter conn, q, _
                            paramName, _
                            LCase$(Trim$(CStr(cell.Offset(0, 1).Value))), _
                            cell.Offset(0, 2).Value, _
                            Trim$(CStr(cell.Offset(0, 3).Value))
        End If
        Set cell = cell.Offset(1, 0)
    Loop
End Sub

Private Sub SetOneParameter(conn As Object, q As Object, ByVal paramName As String, _
                            ByVal paramType As String, ByVal rawValue As Variant, ByVal objectName As String)
    Dim d As Date
    Dim valueList As Object
    Dim part As Variant

    On Error GoTo ParamFailed
    Select Case paramType
        Case "дата"
            If Trim$(CStr(rawValue)) = "" Then
                q.УстановитьПараметр paramName, conn.NewObject("Дата", 1, 1, 1, 0, 0, 0)
            ElseIf IsDate(rawValue) Then
                d = CDate(rawValue)
                q.УстановитьПараметр paramName, _
                    conn.NewObject("Дата", Year(d), Month(d), Day(d), Hour(d), Minute(d), Second(d))
            Else
                RaiseUser "значение «" & rawValue & "» не является датой."
            End If

        Case "число"
            If Not IsNumeric(rawValue) Then RaiseUser "значение «" & rawValue & "» не является числом."
            q.УстановитьПараметр paramName, CDbl(rawValue)

        Case "строка"
            q.УстановитьПараметр paramName, CStr(rawValue)

        Case "булево"
            q.УстановитьПараметр paramName, ToBoolean(rawValue)

        Case "справочник"
            q.УстановитьПараметр paramName, FindCatalogItem(conn, objectName, Trim$(CStr(rawValue)))

        Case "справочникпокоду"
            q.УстановитьПараметр paramName, FindCatalogItemByCode(conn, objectName, rawValue)

        Case "списоксправочник"
            Set valueList = conn.NewObject("СписокЗначений")
            For Each part In Split(CStr(rawValue), ";")
                If Trim$(part) <> "" Then valueList.Добавить FindCatalogItem(conn, objectName, Trim$(part))
            Next part
            If valueList.Count() = 0 Then RaiseUser "список значений пуст."
            q.УстановитьПараметр paramName, valueList

        Case "перечисление"
            q.УстановитьПараметр paramName, FindEnumValue(conn, objectName, Trim$(CStr(rawValue)))

        Case ""
            RaiseUser "не указан тип (колонка «Тип»)."

        Case Else
            RaiseUser "неизвестный тип «" & paramType & "»."
    End Select
    Exit Sub

ParamFailed:
    Err.Raise ERR_USER, "Exchange1C", "Параметр «" & paramName & "»: " & Err.Description
End Sub

Private Function ToBoolean(ByVal v As Variant) As Boolean
    If VarType(v) = vbBoolean Then
        ToBoolean = v
        Exit Function
    End If
    Select Case LCase$(Trim$(CStr(v)))
        Case "истина", "true", "да", "1": ToBoolean = True
        Case "ложь", "false", "нет", "0", "": ToBoolean = False
        Case Else: RaiseUser "значение «" & v & "» не является булевым (ИСТИНА/ЛОЖЬ)."
    End Select
End Function

' Поиск элемента справочника по ТОЧНОМУ наименованию; не найден - ошибка, а не пустая ссылка
Private Function FindCatalogItem(conn As Object, ByVal catalogName As String, ByVal itemName As String) As Object
    Dim manager As Object
    Dim ref As Object

    If catalogName = "" Then RaiseUser "не указано имя справочника (колонка «Объект 1С»)."
    If itemName = "" Then RaiseUser "не указано наименование элемента справочника «" & catalogName & "»."

    Set manager = GetManager(conn.Справочники, catalogName, "Справочник")
    Set ref = manager.НайтиПоНаименованию(itemName, True)
    If ref.Пустая() Then RaiseUser "в справочнике «" & catalogName & "» не найден элемент «" & itemName & "»."
    Set FindCatalogItem = ref
End Function

' Поиск по коду. Текст в ячейке - строковый код (ведущие нули важны), число - числовой код
Private Function FindCatalogItemByCode(conn As Object, ByVal catalogName As String, ByVal code As Variant) As Object
    Dim manager As Object
    Dim ref As Object

    If catalogName = "" Then RaiseUser "не указано имя справочника (колонка «Объект 1С»)."
    If Trim$(CStr(code)) = "" Then RaiseUser "не указан код элемента справочника «" & catalogName & "»."
    If VarType(code) = vbString Then code = Trim$(code)

    Set manager = GetManager(conn.Справочники, catalogName, "Справочник")
    Set ref = manager.НайтиПоКоду(code)
    If ref.Пустая() Then RaiseUser "в справочнике «" & catalogName & "» не найден элемент с кодом «" & code & "»."
    Set FindCatalogItemByCode = ref
End Function

Private Function FindEnumValue(conn As Object, ByVal enumName As String, ByVal valueName As String) As Object
    Dim manager As Object
    Dim ref As Object

    If enumName = "" Then RaiseUser "не указано имя перечисления (колонка «Объект 1С»)."
    If valueName = "" Then RaiseUser "не указано значение перечисления «" & enumName & "»."

    Set manager = GetManager(conn.Перечисления, enumName, "Перечисление")
    On Error Resume Next
    Set ref = CallByName(manager, valueName, VbGet)
    On Error GoTo 0
    If ref Is Nothing Then RaiseUser "в перечислении «" & enumName & "» нет значения «" & valueName & _
                                     "» (нужно имя значения из конфигуратора, а не синоним)."
    Set FindEnumValue = ref
End Function

Private Function GetManager(managers As Object, ByVal objectName As String, ByVal kind As String) As Object
    On Error Resume Next
    Set GetManager = CallByName(managers, objectName, VbGet)
    On Error GoTo 0
    If GetManager Is Nothing Then RaiseUser kind & " «" & objectName & "» не найден в конфигурации 1С."
End Function

'------------------------------------------------------------------------------
' Выгрузка на лист
'------------------------------------------------------------------------------
' Возвращает количество строк данных; colsCount - количество колонок
Private Function ExportData(qResult As Object, conn As Object, ByRef colsCount As Long) As Long
    Dim ws As Worksheet
    Dim sel As Object, col As Object
    Dim data() As Variant
    Dim rowOffset As Long, colOffset As Long
    Dim rowsTotal As Long, i As Long, j As Long
    Dim asText As Boolean
    Dim headerRows As Long
    Dim target As Range

    Set ws = GetTargetSheet()
    rowOffset = SettingLong(NM_ROW_OFFSET)
    colOffset = SettingLong(NM_COL_OFFSET)
    asText = (LCase$(SettingText(NM_MODE)) = "текст")
    headerRows = IIf(LCase$(OptionalSettingText(NM_HEADERS, "Да")) = "нет", 0, 1)

    colsCount = qResult.Columns.Count()
    If colsCount = 0 Then RaiseUser "Запрос не вернул колонок."

    Set sel = qResult.Выбрать()
    rowsTotal = sel.Count()

    If rowsTotal + headerRows = 0 Then
        ' Нечего выводить: без заголовков и без строк
        ClearPreviousOutput ws, rowOffset, colOffset, colsCount
        On Error Resume Next
        ThisWorkbook.Names(NM_LAST_OUTPUT).Delete
        On Error GoTo 0
        Exit Function
    End If

    ' Массив под точный размер: [строка заголовков], далее данные
    ReDim data(1 To rowsTotal + headerRows, 1 To colsCount)
    If headerRows = 1 Then
        j = 0
        For Each col In qResult.Columns
            j = j + 1
            data(1, j) = col.Name
        Next col
    End If

    i = headerRows
    Do While sel.Следующий()
        i = i + 1
        For j = 1 To colsCount
            data(i, j) = ToCellValue(conn, sel.Get(j - 1), asText)
        Next j
        If i Mod 1000 = 0 Then
            Application.StatusBar = "Обмен с 1С: обработано " & (i - headerRows) & " из " & rowsTotal
            DoEvents
        End If
    Loop

    ' Очистка - только после успешного чтения: при ошибке старые данные остаются на месте
    ClearPreviousOutput ws, rowOffset, colOffset, colsCount
    Set target = ws.Cells(rowOffset + 1, colOffset + 1).Resize(rowsTotal + headerRows, colsCount)
    target.Value = data

    ' Запомнить область выгрузки, чтобы в следующий раз очистить ровно её
    ThisWorkbook.Names.Add Name:=NM_LAST_OUTPUT, _
                           RefersTo:="='" & Replace(ws.Name, "'", "''") & "'!" & target.Address, _
                           Visible:=False
    ExportData = i - headerRows
End Function

Private Function GetTargetSheet() As Worksheet
    Dim sheetName As String
    Dim ws As Worksheet

    sheetName = SettingText(NM_SHEET)
    If sheetName = "" Then
        If TypeName(ThisWorkbook.ActiveSheet) <> "Worksheet" Then RaiseUser "Активный лист не является рабочим листом."
        Set ws = ThisWorkbook.ActiveSheet
    Else
        On Error Resume Next
        Set ws = ThisWorkbook.Worksheets(sheetName)
        On Error GoTo 0
        If ws Is Nothing Then
            Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
            ws.Name = sheetName
        End If
    End If

    If ws.Name = Setting(NM_QUERY).Worksheet.Name Then
        RaiseUser "Лист-приёмник совпадает с листом настроек - выгрузка затёрла бы настройки."
    End If
    Set GetTargetSheet = ws
End Function

' Очищает содержимое (форматы сохраняются): прошлую выгрузку и колонки новой - до конца занятой области
Private Sub ClearPreviousOutput(ws As Worksheet, ByVal rowOffset As Long, ByVal colOffset As Long, ByVal colsCount As Long)
    Dim prev As Range
    Dim lastRow As Long

    On Error Resume Next
    Set prev = ThisWorkbook.Names(NM_LAST_OUTPUT).RefersToRange
    On Error GoTo 0
    If Not prev Is Nothing Then
        If prev.Worksheet.Name = ws.Name Then prev.ClearContents
    End If

    With ws.UsedRange
        lastRow = .Row + .Rows.Count - 1
    End With
    If lastRow > rowOffset Then
        ws.Range(ws.Cells(rowOffset + 1, colOffset + 1), ws.Cells(lastRow, colOffset + colsCount)).ClearContents
    End If
End Sub

' Значение 1С -> значение ячейки.
' Режим «Значения»: числа/даты/булево как есть, строки и ссылки - текстом.
' Режим «Текст»: всё через String (как в прежнем макросе).
Private Function ToCellValue(conn As Object, ByVal v As Variant, ByVal asText As Boolean) As Variant
    If IsObject(v) Then
        ToCellValue = AsCellText(conn.String(v), Not asText)
    ElseIf IsNull(v) Or IsEmpty(v) Then
        ' Неопределено / NULL -> пустая ячейка
    ElseIf asText Then
        ToCellValue = AsCellText(conn.String(v), False)
    ElseIf VarType(v) = vbString Then
        ToCellValue = AsCellText(CStr(v), True)
    ElseIf VarType(v) = vbDate Then
        If Year(v) >= 1900 Then ToCellValue = v      ' пустая дата 1С -> пустая ячейка
    Else
        ToCellValue = v
    End If
End Function

' forceText: апостроф, чтобы Excel не превратил «00123» в 123 и «1-2» в дату
Private Function AsCellText(ByVal s As String, ByVal forceText As Boolean) As String
    If Len(s) > MAX_CELL_TEXT Then s = Left$(s, MAX_CELL_TEXT)
    If forceText Or Left$(s, 1) = "=" Then s = "'" & s
    AsCellText = s
End Function

'------------------------------------------------------------------------------
' Служебное
'------------------------------------------------------------------------------
Private Sub RaiseUser(ByVal message As String)
    Err.Raise ERR_USER, "Exchange1C", message
End Sub

Private Sub RestoreApp(ByVal prevCalc As Long)
    On Error Resume Next
    Application.StatusBar = False
    Application.Calculation = prevCalc
    Application.ScreenUpdating = True
End Sub
