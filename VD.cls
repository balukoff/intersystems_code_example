Class Charges.DropFinance Extends (%Persistent, ESystem.JSON.Adaptor)
{

/// Выпадающие доходы
/// Вид продукции
Property Prod As %Integer;

/// услуга
Property Item As %Integer;

/// Единица измерения 
Property Unit As Refs.Unit;

/// Бухгалтерский период
Property BPeriod As %Library.Date;

/// Площадь помещения
Property Square As %Float;

/// Количество человек на дату
Property Humans As %Float;

/// лицевой счет
Property facenum As %String;

/// Тариф
Property Tax As %Float;

/// Договор
Property Contract As Contracts.EPhDogovor;

/// Норматив
Property VNorm As %Float;

/// Объем потребления, порезан до базового
Property Vpotr As %Float;

/// Начислено за период  - денех
Property Summ As %Float;

/// Сумма к возмещению по услуге 
Property VDSum As %Float;

/// Дата операции
Property CDate As %Date [ InitialExpression = {+$H}, Required ];

/// Метод начисления
/// 1-ипу,2-норматив,3-одпу
Property serviceType As %String;

/// Тип периода - "BASE" - это базовый
/// Пустой и все остальное - это все остальное
Property periodType As %String;

Property ChangedBy As Auth.SysUser;

Index facenum On facenum;

Index BPeriod On BPeriod;

Query DgidByFacenum(facenum As %String) As %Library.SQLQuery(CONTAINID = 1, ROWSPEC = "ID:%Integer, Item:%Integer")
{
 select distinct Contract as ID, Item from Charges.DropFinance where Contract->facenum=:facenum and Contract->status=0
}

Query RowsByFacenum(facenum As %String) As %Library.SQLQuery(ROWSPEC = "ID:%Integer, Item:%Integer")
{
 select Contract as ID, Item from Charges.DropFinance where facenum = :facenum
}

Query getBaseFacenum(
	facenum As %String,
	td1 As %Date) As %Library.SQLQuery(ROWSPEC = "ID:%Integer, Item:%Integer")
{
 select Contract as ID, Item from Charges.DropFinance where facenum = :facenum and BPeriod = :td1 and periodType = 'BASE'
}

/// пишем лог - если mainLog = 1 - значит это основной лог, в папке логов
/// если mainLog = 0 - этот лог создается в папке юзера, с датой
ClassMethod doLog(
	text As %String,
	logfile As %String = "dropfinance",
	mainLog As %Boolean = 1)
{
 s user = ##class(Auth.SysUser).CurrentUser()
 //s text = text_", Пользователь: "_user.UserName
 if (mainLog = 0){
  s tdate = $replace($zd(+$H, 4), "/", "_")
  s status = ##class(ESystem.Log).SaveToFile(text, logfile_"_"_tdate_".log","ExportPath","",0,user.UserName_"/")
 }else{
  s status = ##class(ESystem.Log).SaveToFile(text, logfile_".log","LogDir","",0,"")
 }
 q status
}

ClassMethod doHistory(
	facenum As %String,
	operation As %String)
{
 q ##class(Charges.DropFinanceLog).Add(facenum, operation)
}

ClassMethod GetSumBaseVD(
	BPeriod As %Date,
	facenum As %String)
{
 s base = 0
 &sql(select sum(VDSum) into :base from Charges.DropFinance where BPeriod = :BPeriod and facenum = :facenum and periodType = 'BASE')
 q base
}

ClassMethod getDFact() As %List
{
 s period = %request.Get("period")
 s facenum = %request.Get("facenum") 
 s ws = ##class(%ZEN.proxyObject).%New()
 s td1 = $zdh(period, 4)
 /// газ
 s (gas, ee, gassum, eesum) = 0
 &sql(select VPotr, Summ into :gas, :gassum from Charges.DropFinance where BPeriod = :td1 and facenum = :facenum and Item = 1001 and serviceType = 1)
 &sql(select VPotr, Summ into :ee,:eesum from Charges.DropFinance where BPeriod = :td1 and facenum = :facenum and Item = 1002 and serviceType = 1)
 s ws.eepotr = ee, ws.gaspotr = gas, ws.gassum = gassum, ws.eesum = eesum
 q ws
}

///  p1 - факт газ, p2 - сумма газ, p3 - факт ээ, p4 - сумма ээ,
ClassMethod goFact(
	p1 As %Float,
	p2 As %Float,
	p3 As %Float,
	p4 As %Float,
	facenum As %String) As %Boolean
{
	s ws = ##class(%ZEN.proxyObject).%New()
	s period      = %request.Get("period")
	s facenum     = %request.Get("facenum")
	s elcheck     = %request.Get("elcheck")
	s gascheck    = %request.Get("gascheck")
	s ws.gascheck = gascheck
	s ws.elcheck  = elcheck
	s ws.facenum = facenum
	s ws.p1 = p1
	s ws.p2 = p2
	s ws.p3 = p3
	s ws.p4 = p4
	s status = 0

	s ws.error = 0
	s td1 = $zdh(period, 4)
	
	s dgID = ..getDgByFacenum(facenum)
	s houseid = ##class(Contracts.EPhDogovor).HouseDg(dgID)
	s serviceType = 1
	
	/// gas
	s gasItem = 1001
	s gasProd = ..getProdByItem(gasItem)
	
	s gastar = ##class(Charges.DropFinance).getGasTariffbyHouse(houseid, td1)

	s ctax = ..GetCurTax(gasItem, period)
	
	//s ws.tax = $lg(ctax, 3)
	s (taxunitb, taxunitc) = $lg(ctax, 3)
    s tax = gastar
 	
 	s vd = 0
	s cdate = +$H
	if (+dgID '= 0){
	 s sqhum = $lfs(##class(Contracts.EPhDogovor).CountJilSq(dgID, td1, td1, 0), "^")
	}
	s humans = $lg(sqhum, 1)
	s square = $lg(sqhum, 2)
	s BPeriod = td1
	
	//s ws.period = period
	//s ws.tax = tax
		
	if (+gascheck = 1){
	
	s row = $lb(, taxunitc, BPeriod, 0, gasItem, gasProd, p2, tax, vd, humans, p1, humans, square, facenum, serviceType)
	do ..DeleteFacenum(facenum, gasItem, td1)
	 s status = ..writeRow(row)
	
	if (status '= 1){
	 s ws.error = 1
	 q ws
	}
	
	}
	
	/// electro	
	s eeItem  = 1002
	s eeProd = ..getProdByItem(eeItem)
	 
	 /// определяем, есть ли на доме газ
	s gasBlago = ##class(Address.EHouseDesc).getGasBlagoByHouse(houseid)
	if (gasBlago = ""){
	  /// значит для эл плит
	 s el = 1
	}else{
	 s el = 0	 
	}
	
	 s tax = ..GetCurTax(eeItem, period, el)
	 s (basetaxa, currtaxa, taxprodc) = $lg(tax, 2)
	 s (taxunitb, taxunitc) = $lg(tax, 3)
	 s tax = $lg(tax, 2)
	 //s ws.taxunit = taxunitc	
	
	if (+elcheck = 1){
	 s row = $lb(, taxunitc, BPeriod, 0, eeItem, eeProd, p4, tax, vd, humans, p3, humans, square, facenum, serviceType)
	 do ..DeleteFacenum(facenum, eeItem, td1)
	 s status = ..writeRow(row)
	 
	 if (status '= 1){
	  s ws.error = 1	
	  q ws
	 }

	}

 	q ws
}

/// Количество ВД начислений по ЛС и периоду
ClassMethod getFactVDbyLS(
	facenum As %String,
	td1 As %Date,
	td2 As %Date) As %Float
{
	s vd = 0
	&sql(select nvl(abs(sum(Summ)), 0) into :vd from Charges.EChargesA where Contract->facenum = :facenum 
	     and ToDataE between :td1 and :td2 and status = 0 and Contract->Status = 0 and Type = 40)
	do ..doLog("select nvl(abs(sum(Summ)), 0) from Charges.EChargesA where Contract->facenum = "_facenum 
	     _" and ToDataE between "_td1_" and "_td2_" and status = 0 and Contract->Status = 0 and Type = 40")
	q vd
}

ClassMethod getFirstContractId(
	facenum As %String,
	item As %Integer,
	td1 As %Date) As %String
{
	s id = 0
	&sql(select top 1 ID into :id from Charges.DropFinance where facenum = :facenum  and BPeriod = :td1)
	q id
}

ClassMethod loadFile() As %Status
{
  #; был передан файл, поэтому ответим браузеру, о том что приняли файл и как
  if $d(%request.Data("loadFile")) {
    if $lv(%loadFileSuccess),$lg(%loadFileSuccess,1) {
      #; файл принят удачно, ответим об удачном приеме и отправим имя файла и его размер
      w "{""success"":true,",
        """fileName"":"""_$lg(%loadFileSuccess,2)_""",",
        """fileSize"":"""_$lg(%loadFileSuccess,3)_"""}"
    } else {
      #; произошла ошибка при приеме файла
      w "{""error"":""Error load file""}"
    }
    q $$$OK
  }
}

ClassMethod OnPreHTTP() As %Boolean [ ServerOnly = 1 ]
{
  #; Передан файл
  if $d(%request.Data("loadFile")) {
    s %loadFileSuccess=0
    #; поле с файлом
    s FieldName="qqfile"
    #; получим содержимое файла
    i %request.IsDefinedMimeData(FieldName,1) {
      s ContentType=%request.MimeData(FieldName,1).ContentType
      s Content=%request.MimeData(FieldName,1)
    } else {
      s ContentType=%request.ContentType
      s Content=%request.Content
    }
    s:FieldName'="" fileName=$g(%request.Data(FieldName,1))
    #; если файл получен, и он не нулевого размера, соберем информацию по нему
    i $isobject(Content),Content.Size>0 s %loadFileSuccess=$lb(1,$g(fileName),Content.Size)
    q 1
  }
  q 1
}

ClassMethod GetFullFacenumSumm(
	BPeriod As %Date,
	facenum As %String,
	baseFlag As %Integer = 0)
{
 s base = 0
 if (baseFlag = 0){
 
  s data = ##class(Charges.DropFinance).getFaceVD(facenum, $zdate(BPeriod, 4), 0)
  s list =  ##class(Charges.DropFinance).Parce(data) 
	for i=1:1:$ll(list){
	   s vl = $list(list, i)	  
	   s base = base + $lg(vl,10)
	  }
  
  }
 else{
  &sql(select sum(Summ) into :base from Charges.DropFinance where BPeriod = :BPeriod and facenum = :facenum and periodType = 'BASE')
 }
 q base
}

/// выбирает потребление по услуге по дате, лицевому
ClassMethod getPotrBase(
	facenum As %String,
	td1 As %Date,
	item As %Integer) As %Float
{
	s po = 0
	&sql(select VPotr into :po from Charges.DropFinance where item = :item and facenum = :facenum and BPeriod = :td1 and periodType = 'BASE')
	q po
}

/// метод подсчитывает сумму к возмещению месяца по лицевому
ClassMethod getCalculateVD(
	facenum As %String,
	td1 As %Date)
{
 s (currentSumm, baseSumm) = 0
 s parts = $lfs(..GetPrevYear(td1), "^"), vd = 0
 s baseperiod = $zdh($lg(parts, 1), 4)
 s currentSumm = ..GetFullFacenumSumm(td1, facenum)
 s baseSumm = ..GetFullFacenumSumm(baseperiod, facenum, 1)
 s basevd = ..GetSumBaseVD(baseperiod, facenum)
 s pindex =  ##class(Refs.EndPointIndex).GetActual(td1)
 s delta = (baseSumm - basevd)
 s delta = delta + ((delta/100) * pindex)
 s vd = currentSumm - delta
 q vd
}

/// Метод выбирает базовые зафиксированные данные, если таковые имеются
ClassMethod getBaseFixed(
	dgID As %String,
	d1 As %Date,
	value As %String)
{
 s result = -1
 &sql(select Summ, Item, VPotr into :summ, :item, :vpotr 
 from Charges.DropFinance where Contract = :dgID and BPeriod = :d1)
 if SQLCODE q result
 q $lb($lb(summ, item, vpotr))
}

ClassMethod DeleteFacenum(
	facenum As %String,
	Item As %Integer,
	td1 As %Date,
	base As %Integer = 0) As %Boolean
{
   s success = 1

   &sql(delete from Charges.DropFinance where facenum = :facenum and BPeriod = :td1 and Item = :Item and periodType is NULL)
   do ..doHistory(facenum, "Удаление лицевого "_facenum_", период: "_$zd(td1, 4)_", услуга: "_Item)
   if (SQLCODE){
    if (SQLCODE '= 100){
     s success = 0
    }
   }
   q success
}

ClassMethod DeleteFullFacenum(
	facenum As %String,
	td1 As %Date) As %Boolean
{
   s success = 1
   
   &sql(delete from Charges.DropFinance where facenum = :facenum and BPeriod = :td1)
   //do ..doLog("Полное удаление лицевого "_facenum_", период: "_$zd(td1))
   do ..doHistory(facenum, "Полное удаление ЛС за период "_$zd(td1, 4))
   if (SQLCODE){
    if (SQLCODE '= 100){
     s success = 0
    }
   }
   q success
}

/// берет базовые данные по услуге и лицевому счету
ClassMethod getVD(
	facenum As %String,
	item As %Integer,
	td1 As %Date) As %ListOfObjects
{
 s list = ##class(%ZEN.proxyObject).%New()
 &sql(select VPotr, VNorm, Tax, Summ, VDSum, Square, Prod, Humans, Unit into :potr, :norm, :tax, :summ, :vd, :square, :prod, :humans, :unit
      from Charges.DropFinance 
      where facenum = :facenum and item = :item and BPeriod = :td1)
 s list.potr = potr
 s list.norm = norm
 s list.tax  = tax
 s list.summ = summ
 s list.vd   = vd
 s list.prod = prod
 s list.square = square
 s list.unit = unit
 s list.humans = humans
 q list
}

ClassMethod WorkCurrentFix(
	facenum As %String,
	period As %Date,
	Item As %Integer = 0,
	ot As %Integer = 0) As %Boolean
{
  s success = 1	
 /// проверяем, если это услуги 1001 или 1002 - факт
 s exist = 0 
  if ((Item = 1001) || (Item = 1002)){
  &sql(select count(ID) into :exist from Charges.DropFinance 
      where Item = :Item and facenum = :facenum and BPeriod = :period and serviceType = 1 and periodType is NULL) 
	  do ..doLog("select top 1 from Charges.DropFinance where Item = "_Item_" and facenum = "_facenum_" and BPeriod = "_$zd(period, 4)_" and serviceType = 1 and periodType is NULL")
  }
  
   if (+exist = 0){ 
    do ..DeleteFacenum(facenum, Item, period)
    do ..doLog("Удаление лицевого при пересчете "_facenum_", период: "_$zd(period, 4)_", услуга: "_Item_"; ")
    do ..doHistory(facenum, "Удален ЛС при пересчете по услуге: "_Item_" за период "_$zd(period, 4))
   }else{
    do ..doLog("Удаление лицевого при пересчете не нужно: "_facenum_", период: "_$zd(period, 4)_", услуга: "_Item_"; Есть факт; exist="_exist)
   }
	     s calc = ..Calculate(0, $zd(period, 4), 0, Item, facenum)
	     s basePeriod = $System.SQL.DATEPART("YYYY", period) - 1
	     s base = $zdh("01/12/"_basePeriod, 4)
	     s basePO = ..getPotrBase(facenum, base, Item)
	     do ..doLog("Получено из calculate "_calc)
	     s vcalc = $lfs(calc, "&")
		 w:ot=1 calc, !
		 s list = $lfs($lg(vcalc, 1), "^")
		 // продукция
		 s prod     = $lg(list, 14)
		 // договор по типу и лицевому
		 s dog = ..getDgByFacenum(facenum, prod)
		 s humans   = $lg(list, 15)
		 if (+exist = 0){ 
		  s serv     = $lg(list, 17)
		 }else{
		  s serv = 1	 
		 }
		 s square   = $lg(list, 16)
		 s tax      = $lg(list, 11)
		 s vdsum    = 0
		 s vnorm    = $lg(list, 8)
		 s vpotr    = $lg(list, 9)
		 if (vpotr >= basePO){
		  s vpotr = basePO
		 }
		 s fullSumm = vpotr * tax
		 s unit     = $lg(list, 3)
		 
		 s row = $lb(, unit, period , +dog, Item, prod , fullSumm , tax, vdsum, vnorm, vpotr, humans, square, facenum, serv)
		 //do ..doLog("Промежуточные данные после calc: "_$lts(row, "|"),,0)	   
		 if (+exist = 0){ 
		  s result = ..writeRow(row)
		 }else{
		  s result = 1
		 }
	     if (result = 1){
		  do ..doLog("Записан ЛС: "_facenum_", Услуга: "_Item,,0)	   
		  do ..doHistory(facenum, "Записан ЛС при пересчете по услуге: "_Item_" за период "_$zd(period, 4)_" на "_fullSumm)  
		 }
 
 	if (+exist '= 0){
 	 do ..doLog("Обработан ЛС: "_facenum_", Услуга: "_Item_"; Факт",,0)
 	}
 	
	q success
}

/// Метод пересчитывает(фиксирует) текущие выпадающие + добавляет начисления по коду 40
ClassMethod CalcCurrentFix(
	facenum As %String,
	td1 As %Library.Date,
	debug As %Integer = 0,
	NachType As %Integer = 40,
	minusCorrection = 0) As %Boolean
{
	 s period = ##class(Charges.EProdKind).BeginCalcPeriodGet(2)
	 s pindex = ##class(Refs.EndPointIndex).GetActual(td1)

	 s currentY = $System.SQL.DATEPART("YYYY", td1)
	 s currentM = $System.SQL.DATEPART("MM", td1)
	 
	 s ct = ##class(Refs.BasePeriod).getActual(currentY, currentM)

	 /// если установлен флаг фиксации периода, который не является актуальным по бух периоду
	 if (ct = -1){
	  s parts = $lfs(..GetPrevYear(td1), "^")
	  s base = $zdh($lg(parts, 1), 4)
	 }else{
	  s base = ct
	 }
	 s rs=##class(%ResultSet).%New("Charges.DropFinance.getBaseFacenum")
	 s success = 1
	 Do rs.Execute(facenum, base)
	 while (rs.Next()){
	  s Item = rs.Get("Item")
	  do ..doLog("---Текущая услуга: "_Item_" для ЛС: "_facenum_" и даты: "_$zd(td1, 4),,1)
	  w:debug "Текущая услуга: "_Item, !
	  do ..WorkCurrentFix(facenum, td1, Item, debug)
	  do ..doLog("---Завершил",,1)	 
	 // if (success = 0) q 
	 }
     s dgID = ..getDgByFacenum(facenum)
    /// пишем начисления по вд на первый договор в списке лицевого счета
     s vd = ..getCalculateVD(facenum, td1)
     do ..doLog("Сумма ВД для "_facenum_"="_vd,,1)
     s vd = $fn(vd, "", 2)
     //q vd
     w:debug "vd="_vd, !
     if (vd < 0) s vd = 0
	 
	 s pd = ##class(Contracts.EPhDogovor).getProdDg(dgID)
	 s item = ##class(Charges.EServKind).GetRootItem(pd)
	 //w "vd="_vd_", minusCorrection="_minusCorrection
	 if ((vd '= 0) || (minusCorrection = 1)){
	
	  do ##class(Charges.ChargesCalc).Agr(dgID, item, NachType, 0, -vd, td1, td1, 4)
	 /// сюда вешаем на первый договор в %Id всю сумму ВД
	  s id = ..getFirstContractId(facenum, td1)

	  &sql(update Charges.DropFinance set VDSum = :vd 
	      where ID = (select top 1 ID from Charges.DropFinance where BPeriod = :td1 and Prod = 2 and facenum = :facenum))
	 do ..doLog("После апдейта SQLCODE="_SQLCODE_"; на сумму "_vd,,1)
	 if (SQLCODE = 0){ s success = 1}
	 else{
		s success = 0
	 }
	 
	 }else{
	  s success = 0	 
	 }
 q success
}

/// проверяет, есть ли начисления 
/// по лицевому
ClassMethod isCalculated(
	facenum As %String,
	td1 As %Date) As %Boolean
{
 s (sum, fl) = 0
 &sql(select sum(Summ) into :sum 
      from Charges.EChargesA 
      where Contract in (select ID from Contracts.EPhDogovor where facenum = :facenum) and ToDataB = :td1 and Type = 40 and status = 0)
  if (+sum '= 0){ 
   s fl = 1
  }
 q fl
}

ClassMethod getRealFact(
	facenum As %String,
	prod As %Integer,
	bperiod As %Date,
	item As %Integer = 0,
	debug As %Integer = 0)
{
	 //s debug = 1
 s bperiod = $zd(bperiod, 4), current = 0
 if (item = 0){
  s item = ##class(Charges.EServKind).GetRootItem(prod)
 }
 w:debug "item="_item, !
 
 s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, item, $zdh(bperiod, 4)), 1)
 s current = $lg(currPO, 3)
 
 /// перекрываем
 
 if ((item = 141) || (item = 143) || (item = 144)){
  /// если ВО	 
   s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, 141, $zdh(bperiod, 4)), 1)
   //zw currPO
   s current = $lg(currPO, 3)
   s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, 143, $zdh(bperiod, 4)), 1)
  // zw currPO
   s current = current + $lg(currPO, 3)
   
   s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, 144, $zdh(bperiod, 4)), 1)
   s current = current + $lg(currPO, 3)
 } 
 
 if (item = 91){
  /// если ГВТС	 
   s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, 91, $zdh(bperiod, 4)), 1)
   s current = $lg(currPO, 3)
   s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, 133, $zdh(bperiod, 4)), 1)
   s current = current + $lg(currPO, 3)
 } 
 
 //  w:debug "currPO="_currPO, !
 
 if ((item = 1001) || (item = 1002)){
  /// есть ли факт
  s SQLText = "select top 1 VPotr from Charges.DropFinance where Item = "_item
  s SQLText = SQLText_" and facenum = "_facenum_" and BPeriod = to_date('"_bperiod_"', 'dd/mm/yyyy') and serviceType = 1"
  s SQLQuery = ##class(%SQL.Statement).%New()
  d SQLQuery.%Prepare(SQLText)
  s DataRow = SQLQuery.%Execute()    
  s count = 0 
  while DataRow.%Next(){
	s current = DataRow.VPotr
	s count = count + 1
  }
 
  if (count = 0){
   /// если нет начислений 
   s vpr = $lfs(..Calculate(0, bperiod, 0, item, facenum), "^")
   s current = $lg(vpr, 18)
   s current = $REPLACE(current, "&", "")
  }
 }else{

 }
 q current
}

ClassMethod getFaceVD(
	facenum As %String,
	td1 As %Library.Date,
	debug As %Integer = 0) As %String
{
	s cachedate = $zdh(td1, 4)
	s period = ..GetPrevYear(cachedate)
	
	s currenty = $System.SQL.DATEPART("YYYY", cachedate)
	s currentm = $System.SQL.DATEPART("MM", cachedate)
	// проверяем, какой базовый период брать - из справочника
	s base = ##class(Refs.BasePeriod).getActual(currenty, currentm)
	if (base = -1){	
	 s parts = $lfs(..GetPrevYear($zdh(td1, 4)), "^")
	 s base = $zdh($lg(parts, 1), 4)
	}else{
	 s base = $zdh(base, 4)	
	}
	
	s current = $zdh("01/"_currentm_"/"_currenty, 4)
	
	s (tres, res) = ""
	w:debug=1 "facenum="_facenum, !
			 /// базовый
			 &sql(declare cr12 cursor for 
			      select Contract, (select Name from Charges.EServKind where Code = v.Item), Summ, Unit, VDSum, VNorm, VPotr, Tax, Item 
			      into  :contract, :name, :summ, :unit, :vdsum, :vnorm, :vpotr, :tax, :item
			      from Charges.DropFinance v 
			      where BPeriod = :base and facenum = :facenum and periodType = 'BASE' 
			      order by Item)
			      
			 &sql(open cr12)
			 
			 for{
				 &sql(fetch cr12)
			     quit:SQLCODE
			     s dgID = contract
			     s res = "^"_name_"^"_unit_"^"_vnorm_"^"_vpotr_"^"_summ_"^"_tax_"^"	 
			     s vbasepotr = vpotr
			     s (name, unit, vnorm, vpotr, summ, tax) = ""
			     
			     w:debug=1 "res1="_res, !
			      /// нет зафиксированного текущего, считаем
			       s row = ..Calculate(0, $zd(current, 4), debug, item, facenum)
			       s row = $lfs(row, "^")
			       
			       s vpotr = $lg(row, 9), sum = $lg(row, 10), vnorm = $lg(row, 4), servType = $lg(row, 17)
			       
			       /// проверяем, был ли факт на газе и электричестве
			        if ((item = 1001) || (item = 1002)){
			        &sql(select VPotr, Summ, VNorm into :v1, :v2, :v3
			             from Charges.DropFinance where facenum = :facenum and Item = :item and BPeriod = :current)
			       if (%ROWCOUNT '= 0){ 
			       	 s vpotr = v1, sum = v2, vnorm = v3
			       }
			   
			       }
			       	
			       s currPO = vpotr
			       s tax = $lg(row, 11)
			       
			       if (vpotr >= vbasepotr){
				      s vpotr = vbasepotr 
				      /// и пересчет
				    } 
				    s sum = vpotr * tax
				     
				   s square = $replace($lg(row, 16), "&", "") 
			       s res = res_$lg(row, 8)_"^"_vpotr_"^"_sum_"^"_$lg(row, 11)_"^"_dgID_"^"_$lg(row, 9)_"^"_$lg(row, 14)_"^"_$lg(row, 15)_"^"_square_"^"_item_"^"_servType_"&"
			       w:debug=1 "res="_res, !
			      
			      s tres = tres_res
			      
			      }
			  //w tres 
			  &sql(close cr12)
	q tres
}

/// А вдруг
/// Удаляет базовый период по facenum и дате базового. Подается текущая дата, метод сам определяет, какой период базовый
ClassMethod RemoveBase(
	facenum As %String,
	d1 As %Date) As %Boolean
{
	do ..doLog("Удаление ЛС: "_facenum_", базового периода: "_d1)
	s period = ..GetPrevYear($zdh(d1, 4))
	s parts = $lfs(..GetPrevYear($zdh(d1, 4)), "^")
	s base = $lg(parts, 1)
	do ..doLog("Базовая дата: "_$lg(parts, 1))
	
	s error = 0
	 &sql(delete from Charges.DropFinance where BPeriod = to_date(:base, 'dd/mm/yyyy') and facenum = :facenum and periodType = 'BASE')
	 if (SQLCODE){ 
	  s error = 1
	  do ..doLog("SQLCODE="_SQLCODE)
	  q
	 }
  q error
}

ClassMethod fixBase(
	facenum As %String,
	d1 As %Date,
	debug As %Integer = 0) As %Boolean
{
  //do ..doLog("Фиксация базового "_facenum_", период: "_$zd(d1))
  do ..doHistory(facenum, "Фиксация базового периода: "_$zd(d1, 4))
  s result = 0
  s list = ..FaceCalc(facenum, d1, debug)
  s list = ..Parce(list)
  s period = $lfs(..GetPrevYear(d1), "^")
  
  s period = $zdh($lg(period, 1), 4)
  
  for i=1:1:$ll(list){
	s vl = $list(list, i)
	s dog      = $lg(vl, 13)
	s humans   = $lg(vl, 15)
	s square   = $lg(vl, 16)
	s fullSumm = $lg(vl, 5)
	s tax      = $lg(vl, 11)
	s prod     = $lg(vl, 14)
	s vdsum    = $lg(vl, 6)
	s vnorm    = $lg(vl, 4)
	s vpotr    = $lg(vl, 5)
	s item     = $lg(vl, 12)
	if (+dog '= 0){
	 &sql(select UnitT->ID into :unit from Tarifs.EEBTarifs ee where Item->ProdKind = :prod)
	}
	s row = $lb(, unit, period , +dog, item, prod , fullSumm , tax, vdsum, vnorm, vpotr, humans, square, facenum)
	s result = ..writeRow(row, "BASE")
  }
 q result
}

// название_услуги^единица_текущая^норматив^базОбъем^СуммаБаз^базТариф^норматив^ОбъемТек^СуммаТек^ТарифТек^КодУслуги^ДогID^КодПродукции^ЧелПроп^Площадь

ClassMethod getDgByEService(
	facenum As %String,
	item As %Integer) As %Integer
{
  s dgID = 0
 /*  &sql(select ID into :dgID from Contracts.EPhDogovor 
       where facenum = :facenum and Type in (select ProdKind from Charges.EServKind where code = :item) and status = 0)
 */
 /// измменил здесь на ProdKind->Code
 &sql(select ID into :dgID from Contracts.EPhDogovor 
        where facenum = :facenum and Type in (select ProdKind->Code from Charges.EServKind where code = :item) and status = 0)
  q dgID
}

ClassMethod getDgByFacenum(
	facenum As %String,
	prod As %Integer = "") As %Integer
{
  s dgID = 0
  /// определим договор тепла, если его нет - возьму первый
  if (+prod = ""){
   s prod = 2
  }
  &sql(select top 1 ID into :dgID from Contracts.EPhDogovor where facenum = :facenum and status = 0 and Type = :prod)
  if (+dgID = 0){    
   &sql(select top 1 ID into :dgID from Contracts.EPhDogovor where facenum = :facenum and status = 0)
  }
  q +dgID
}

/// Метод фиксирует базовый период, который введен ручками
/// на вход подается строка с разделителями и дата
ClassMethod fixBaseManual(
	facenum As %String,
	list As %String,
	d1 As %Date) As %Boolean
{
 do ..doLog("=============Фиксация базового периода для лицевого "_facenum_"==============")
 do ..doHistory(facenum, "Фиксация базового периода: "_$zd(d1, 4)_" вручную")
 s fperiod = d1, result = 0, base = "BASE"
 
 do ..doLog("Исходная строка: "_list)
 
 s list = ..Parce(list)
 s period = $lfs(..GetPrevYear(d1), "^")
 
 
 do ..doLog("Период для базового: "_period)
 for i=1:1:$ll(list){
	s vl = $list(list, i)
	s item = $lg(vl, 1)
	s dgID = ..getDgByEService(facenum, item)
	do ..doLog("Определили договор: "_dgID_", Услугу: "_item)
	s bperiod = $zdh($lg(period, 1), 4)	
	s dog = dgID
	/// определяем код единицы по продукции
	/// людей + площадь
	if (+dgID = 0){
	  /// берем первый же договор по лицевому счету	
	  s dgID = ..getDgByFacenum(facenum)
	  do ..doLog("Переопределили dgID: "_dgID)
	  if (+dgID = 0){
		  s sqhum = $lfs("0^0", "^")
		 }else{
		  s sqhum    = $lfs(##class(Contracts.EPhDogovor).CountJilSq(dgID, d1, d1, 0), "^")	 
		 }
	}else{
	 s sqhum    = $lfs(##class(Contracts.EPhDogovor).CountJilSq(dgID, d1, d1, 0), "^")
	}
	
	s prod = ..getProdByItem(item)
	do ..doLog("Определили продукцию: "_prod)
	
	 if ((prod = 9) || (prod = 13) || (prod = 14) || (prod = 1) || (prod = 15)){
	    s humans = $lg(vl, 2)
	    s square   = $lg(sqhum, 2)
	   }else{
		s humans = $lg(sqhum, 1)
	    s square   = $lg(vl, 2)
	   }
	
	do ..doLog("Определяем единицу измерения на дату: "_$zd(d1, 4))

	s fullSumm = $lg(vl, 5)
	s tax      = $lg(vl, 4)
	s vdsum    = $lg(vl, 6)
	s vnorm    = $lg(vl, 2)
	s vpotr    = $lg(vl, 3)
	s service  = $lg(vl, 7)
	
	 /// определяем по facenum + item
	
	s unit = $lg(..GetCurTax(item, $zd(d1, 4)), 3)
	
	do ..doLog("Определили единицу измерения: "_unit)
	
 	s row = $lb(, unit, bperiod , +dog, item, prod , fullSumm , tax, vdsum, vnorm, vpotr, humans, square, facenum, service)
	s result = ..writeRow(row, base)
	do ..doLog("Результат записи в БД: "_result)
  }

 q result
}

/// ставит флаг в объекте - удален объект
ClassMethod setDeleteKey(
	list As %ListOfObjects,
	facenum As %String)
{
   s key = ""
   while (list.GetNext(.key) '= "") {
   s row = list.GetAt(key)	
   if (row.facenum = facenum){
	 s list.GetAt(key).deleted = 1	
	 q
	}
	
 }
 q list
}

/// проверяет существование ЛС в пуле ЛС
ClassMethod isKeyExists(
	list As %ListOfObjects,
	facenum As %String,
	deleted As %Integer = 0) As %Boolean
{
 s key = "", count = 0
 while (list.GetNext(.key) '= "") {
	s row = list.GetAt(key)	
	if (row.facenum = facenum){
	 if (deleted '= 0){
	  if (row.deleted = 1){
	   s count = count + 1
	  }
	 }else{
	  s count = count + 1
	 }
	 
	}
 }	
 if (count > 0){
  q 1	 
 }else{
  q 0	 
 }
}

/// метод берет все лицевые счета из утвержденного формата файла
ClassMethod getLSListFromFile(
	filename As %String,
	debug As %Integer = 0) As %ListOfObjects
{
 //s filename = $$GetGVar^EK("MODELSPATH")_filename
 //s pperiod = $zdh("01/12/"_($System.SQL.DATEPART("YYYY", +$H) - 1), 4)
 set file = ##class(%FileCharacterStream).%New()
 set file.Filename = filename
 set file.TranslateTable = "RAW"
 set fnum = ##class(%ListOfObjects).%New()
   
   while 'file.AtEnd {
	set str      = file.ReadLine()
	set row      = $lfs(str, ";")
	set facenum  = +$lg(row, 2)
	if (..isKeyExists(fnum, facenum) = 0){
	  if ((+facenum '= 0) && (+facenum '= 1) && (+facenum '= "")){
	   s obj = ##class(%ZEN.proxyObject).%New()
	   s obj.facenum = facenum
	   s obj.deleted = 0
	   w:debug=1 "facenum = "_facenum, !
	   do fnum.Insert(obj)
	  }
	}	
   }
 q fnum
}

ClassMethod FacenumExists(facenum As %String) As %Boolean
{
 s c = 0
 &sql(select count(*) into :c from Contracts.EPhDogovor where facenum = :facenum)	
 q c
}

ClassMethod isServExists(item As %Integer) As %Boolean
{
  s t = 0
  &sql(select count(*) into :t from Charges.EServKind where Code = :item)
  q t
}

ClassMethod MassImport(filename As %String) As %ListOfObjects
{
	//s pperiod = $zdh("01/12/"_($System.SQL.DATEPART("YYYY", +$H) - 1), 4)
	do ..doLog("------------- Импорт файла для загрузки ВД -----------",,0)
	do ..doHistory("", "Импорт файла для загрузки ")
	s ws = ##class(%ZEN.proxyObject).%New()
	s base = "BASE"
	s ws.error = 0, line = 0
	//do ..doLog("ws.error="_ws.error)
	s filename = $$GetGVar^EK("MODELSPATH")_filename
	
	do ..doLog("Имя файла для импорта: "_filename,,0)
	
	s facenums = ..getLSListFromFile(filename)
	//zw facenums
	//do ..doLog("Получили список лицевых: "_facenums)
	
	set file = ##class(%FileCharacterStream).%New()
	set file.Filename = filename
	set file.TranslateTable = "RAW"
	   while 'file.AtEnd {
		set str = file.ReadLine()
		s id  = $lfs(str, ";")
		//do ..doLog("Строка с файла: "_str,,0)
		if ((+$lg(id, 2) '= 0) && (+$lg(id, 2) '= 1)){
		 s line = line + 1
		 s item        = +$lg(id, 7)
		 s pperiod = $replace($lg(id, 6), ".", "/")
		 s prod = ..getProdByItem(item),
		   facenum     = +$lg(id, 2),
		   unit        = $lg(id, 8),
		   sum         = +$replace($lg(id, 14), ",", "."),
		   tax         = +$replace($lg(id, 11), ",", "."),
		   serviceType = +$lg(id, 12),
		   vdsum       = +$replace($lg(id, 15), ",", "."),
		   vpotr       = +$replace($lg(id, 13), ",", "."),
		   humans      = +$replace($lg(id, 10), ",", "."),
		   square      = +$replace($lg(id, 9), ",", "."),
		   pperiod     = $zdh(pperiod, 4)
		   		   
		    /// проверяем на существование лицевого счета
		   if (+..FacenumExists(facenum) = 0){
			do ..doLog("Ошибка в строке: "_line_", ЛС "_facenum_" не найден",,0)
		    continue
		   }
		   
		   if (+..isServExists(item) = 0){
		    do ..doLog("Ошибка в строке: "_line_", Услуга "_item_" не найдена",,0)		
		    continue
		   }
		   
		   /// нужно определить, какой показатель показывать: для ээ и газа - чел, для отопления - площадь, для гвс, хвс - чел
	       if ((prod = 9) || (prod = 13) || (prod = 14) || (prod = 1) || (prod = 15)){
	        s vnorm = humans
	       }else{
		    s vnorm = square
	       }
		   /// определяем единицу
		   s ut = ""
		   &sql(select top 1 ID into :ut from Refs.Unit where upper(ID) = upper(:unit))
		   s unit = ut
		   s row = $lb(, unit, pperiod, 0, item, prod, sum, tax, vdsum, vnorm, vpotr, humans, square,facenum, serviceType)
		   if (unit = ""){
			do ..doLog("Ошибка в строке: "_line_", Единица измерения "_$lg(id, 8)_" не найдена",,0)   
			continue 
		   }
		   
		   /// удаляем аналогичный
		   /// проверяем - удален ли уже
		   if (..isKeyExists(facenums, facenum, 1) '= 1){
		    do ..doLog("Удаляем базовый период ВД на ЛС: "_facenum,,0)
		    do ..DeleteFullFacenum(facenum, pperiod)
		    /// путь в один конец - при первом проходе устанавливается флаг удаления
		    s facenums = ..setDeleteKey(facenums, facenum)
		   }
		   		   		   
		   s state = ..writeRow(row, base)
		   if ('state){
			s ws.error = 1
			do ..doLog("Ошибка в строке(с первой строки данных): "_line,,0)
			q
		   }
		}else{
			do ..doLog("Ошибка формата файла, строка "_line,,0)
			}
		   
	   }   
  
 q ws
}

ClassMethod getFlatCharges(
	facenum As %String,
	Item As %Integer,
	bperiod As %Date) As %List
{
	s res=""
				 //s bperiod = $zd(bperiod, 4)
				 s startperiod = $zd(bperiod, 4)
				 s endperiod = $zd($SYSTEM.SQL.LASTDAY(bperiod), 4)
				 
				 s SQLQuery = ##class(%SQL.Statement).%New()	
					
				 s (st, sm, dt, tt, tar) = 0
				 
	 s SQLText =  " select Summ sm, CValue cv, DateInvoice di, ServiceType st from Charges.EChargesA "
				 _" where Contract->facenum =  '"_facenum_"' and Item = "_Item
				 _" and monthpo = to_date('"_startperiod_"', 'dd/mm/yyyy') "
                 _" and toDataE between to_date('"_startperiod_"', 'dd/mm/yyyy') and to_date('"_endperiod_"', 'dd/mm/yyyy') "
                 _" and Type not in (30, 31, 33, 34, 40, 41) "
	 
	// w SQLText
	 d SQLQuery.%Prepare(SQLText)
  	 s DataRow = SQLQuery.%Execute()
 	
  	 s stype = 0
  	 while DataRow.%Next(){
	  s st = st + DataRow.sm
	  s sm = sm + DataRow.cv
	  s dt = DataRow.di
	  if ((stype '= DataRow.st) && (stype '= 1)){
	   s stype = DataRow.st 
	  }

  	 }
		//select sm, cv, di, st, round(sm/cv, 2) into :st, :sm, :dt, :tt, :tar		 
	  if (sm '= 0){
	   s tar = st/sm
	  }else{
	   s tar = 0
	  } 
	 
	  s res= $lb(sm, st, dt, stype, tar)
	  kill SQLQuery
	  q res
}

/// Берем чистые начисления для базового
ClassMethod getFlatChargesTest(
	facenum As %String,
	Item As %Integer,
	bperiod As %Date) As %List
{
		s res=""
				 s bperiod = $zd(bperiod, 4)
				 s (st, sm, dt, tt, tar) = 0
				 
				 &sql(select top 1 sm, cv, di, st, round(sm/cv, 2) into :st, :sm, :dt, :tt, :tar 
				      from (
					  select sum(Summ) sm, sum(CValue) cv, DateInvoice di, ServiceType st from Charges.EChargesA
					  where Contract->facenum =  :facenum and Item = :Item and MonthPay = to_date(:bperiod, 'dd/mm/yyyy')
                                      and todatae>=monthpay 
                                      and Type not in (30,31,33,34)
                                      group by 3,4,5
                       )
				  )
				 
		 s res= $lb(sm, st, dt, tt, tar)
		 q res
}

/// Выбрать чистые начисления по 
ClassMethod writeObjectRow(
	row As %ZEN.proxyObject,
	base As %String = "") As %Boolean
{
 s result = 0
 s df = ..%New()
 s df.Unit     =    ##class(Refs.Unit).%OpenId(row.unit) ///единичка
 s df.BPeriod  =    row.bperiod /// бухпериод
 s df.Contract =    ##class(Contracts.EPhDogovor).%OpenId(row.contract) /// id договора
 s df.Item     =    row.item
 s df.Prod     =    row.prod /// продукция
 s df.Summ     = 	row.summ /// сумма
 s df.Tax      =    row.tax  /// тариф
 s df.VDSum    =    row.vdsum
 s df.VNorm    =    row.vnorm
 s df.Vpotr    =    row.vpotr
 s df.CDate    =    +$H
 s df.Humans   =    row.humans
 s df.Square   =    row.square
 s df.facenum  =    row.facenum
 if (row.servicetype '= ""){
  s df.serviceType  = row.servicetype
 }
 
 s user = ##class(Auth.SysUser).CheckUser()
 s user = ##class(Auth.SysUser).%OpenId(user)
 //s fio = ##class(Auth.SysUser).GetFullName(user)
 s df.ChangedBy = user
 
 if (base '= ""){
  s df.periodType = base	 
 }
 
 s rs = df.%Save()
 if (rs){ 
  s result = 1
  do ..doLog("ЛС записан для "_df.Item_", tax="_df.Tax_"; "_df.facenum_"; humans="_df.Humans_"; Unit="_df.Unit.Name_"; object")
 }else{
  do ..doLog("При записи возникла ошибка для item="_df.Item_", tax="_df.Tax_"; "_df.facenum_"; humans="_df.Humans_"; Unit="_df.Unit.Name_"; object")	 
 }
 
 q result
}

ClassMethod isTypeExists(
	facenum As %String,
	Type As %Integer,
	dt1 As %Date,
	dt2 As %Date) As %Library.Boolean
{
	s counter = 0
	&sql(select count(*) into :counter from Contracts.EPhDogovor 
	     where Type = :Type 
	     and facenum = :facenum 
	     and BDate <= to_date(:dt1, 'dd/mm/yyyy') 
	     and EDate >= to_date(:dt2,'dd/mm/yyyy') 
	    )
	q +counter
}

ClassMethod ifChangeNSI(
	dg As %Integer,
	td1 As %Library.Date = 0,
	td2 As %Library.Date = 0) As %Integer
{
	/// по истории смотрим, есть ли смена периода
 set nd=0
 set count = 0 
 for  
 { quit:(nd="")  set bpd=nd, nd=$order(^Contract.EPhDogovorD(dg,"History",nd)) 
	 //w nd, !
	 if nd="" 
	 { set hc=$listget(^Contract.EPhDogovorD(dg),13),sq=$listget(^Contract.EPhDogovorD(dg),18)
	   set sqd=$listget(^Contract.EPhDogovorD(dg),19)
	   //s count = count + 1
	 }
 else 
	 { set hc=$listget(^Contract.EPhDogovorD(dg,"History",nd),6),sq=$listget(^Contract.EPhDogovorD(dg,"History",nd),10)
	   set sqd=$listget(^Contract.EPhDogovorD(dg,"History",nd),11)
	   
	 }
	 if ((bpd >= td1) && (bpd <= td2)){
		 s count = count + 1
		}
 }
 q count
}

/// для редактирования базового
ClassMethod getWholeBasePeriod(
	td1 As %Date,
	facenum As %String) As %ListOfObjects
{
   /// необходимо определить, какой берем месяц в качестве базового
   s vd = 0
   s currentY = $System.SQL.DATEPART("YYYY", td1)
   s currentM = $System.SQL.DATEPART("MM", td1)
   
   s tbase = ##class(Refs.BasePeriod).getActual(currentY, currentM)   
   /// дефолтный сценарий
   if (tbase  = -1){
    s parts = $lfs(..GetPrevYear(td1), "^")
    s baseperiod = $zdh($lg(parts, 1), 4)
   }else{
	s baseperiod = $zdh(tbase, 4)  
   }
   s fnum = ##class(%ListOfObjects).%New()
   s SQLQuery = ##class(%SQL.Statement).%New()	
   s SQLText =  " select * from Charges.DropFinance where periodType = 'BASE' and facenum = '"_facenum_"' and BPeriod = to_date('"_$zd(baseperiod, 4)_"', 'dd/mm/yyyy')"
   d SQLQuery.%Prepare(SQLText)
   s DataRow = SQLQuery.%Execute()
  while DataRow.%Next(){
   s ws = ##class(%ZEN.proxyObject).%New()
   s ws.ID = DataRow.ID
   s ws.Humans = DataRow.Humans
   s ws.Item = DataRow.Item
   s ws.Prod = DataRow.Prod
   s ws.Square = DataRow.Square
   s ws.Summ = DataRow.Summ
   s ws.Tax = DataRow.Tax
   s ws.Unit = DataRow.Unit
   s ws.VDSum = +DataRow.VDSum
   s ws.BPeriod = DataRow.BPeriod
   if ((ws.Prod = 9) || (ws.Prod = 13) || (ws.Prod = 14) || (ws.Prod = 1) || (ws.Prod = 15)){
	    s ws.VNorm = ws.Humans
	   }else{
		s ws.VNorm = ws.Square
	   }
   s ws.VPotr = DataRow.VPotr
   s ws.facenum = DataRow.facenum
   s ws.serviceType = DataRow.serviceType
   do fnum.Insert(ws)
   kill ws
  } 
  q fnum
}

ClassMethod updateBasePeriod(data As %Library.ListOfObjects) As %Integer
{
	// request
  s key = "", list = ""
   // инициируем удаление
  s counter = 0, facenum = ""
   while (data.GetNext(.key) '= "") {
	s row = data.GetAt(key)	
	if (+row.id = 0){continue}
	if (counter '= 0){
	 s list = list_", "
	}
	s list = list_row.id
	s facenum = row.facenum
	s tperiod = row.period
	s counter = counter + 1
   }
   /// текущая дата отправляется ajax
   // посморим, какой брать для базового
      
   s currentY = $System.SQL.DATEPART("YYYY", row.period)
   s currentM = $System.SQL.DATEPART("MM", row.period)
   
   s tbase = ##class(Refs.BasePeriod).getActual(currentY, currentM) 
   if (tbase = -1){
    s parts = $lfs(..GetPrevYear(tperiod), "^")
    s base = $lg(parts, 1)
   }else{
	s base = tbase   
   }

   /// удаляем все ID записи, которые не передались
   /// это значит, что какая-то строка удалена
   s SQLQuery = ##class(%SQL.Statement).%New()	
   s SQLText =  "delete from Charges.DropFinance where ID not in ("_list_") and facenum = '"_facenum_"' "
                                _"and periodType = 'BASE' and BPeriod = to_date('"_base_"', 'dd/mm/yyyy')"
   d SQLQuery.%Prepare(SQLText)
   s DataRow = SQLQuery.%Execute()
   kill SQLQuery
   
   s key = ""
   while (data.GetNext(.key) '= "") {
   s row = data.GetAt(key)	
   /// проверяем, есть ли текущий ID
   s id = row.id, count = 0
   &sql(select count(*) into :count from Charges.DropFinance where ID = :id)
   s success = 0

   s item = row.item, 
     square = row.square, 
     humans = row.humans, 
     vpotr = row.vpotr, 
     tax = row.tax, 
     sum = row.tax * row.vpotr,
     //row.sum, 
     vdsum = row.vdsum, 
     serviceType = row.serviceType,
     period = row.period,
     facenum = row.facenum
     
     s prod = ..getProdByItem(item)
     
	 if ((prod = 9) || (prod = 13) || (prod = 14) || (prod = 1) || (prod = 15)){
	    s vnorm = row.humans
	   }else{
		s vnorm = row.square
	   }

	  s dg = ..getDgByEService(facenum, item)
	  s unit = $lg(..GetCurTax(item, $zd(period, 4)), 3)
	  if (+dg = 0){
	   	s dg = ..getDgByEService(facenum, 11)
	  }

   if (+count = 0){
	   // добавляем
	   // определяем продукцию по услуге 
	  s row = $lb(, unit, $zdh(base, 4) , +dg, item, prod , sum , tax, vdsum, vnorm, vpotr, humans, square, facenum, serviceType)

	  s result = ..writeRow(row, "BASE")
	  if ('result){
	   s success = success + 1	  
	  }
	    
	 }else{
	 // обновляем
	 s user = ##class(Auth.SysUser).CheckUser()
	 s user = ##class(Auth.SysUser).%OpenId(user)
	 
	 s contract = ##class(Contracts.EPhDogovor).%OpenId(dg)
	 
	 s df = ..%OpenId(id)
	 s df.Item = item
	 s df.VNorm = vnorm
	 s df.VDSum = vdsum 
	 s df.serviceType = serviceType 
	 s df.Tax = tax
	 s df.Vpotr = vpotr
	 s df.Humans = humans
	 s df.Square = square
	 s df.Summ = sum
	 s df.Contract = contract
	 s df.ChangedBy = user
	 s rs = df.%Save()
	 if (+rs '= 1){
	  s success = success + 1
	 }
	}
	   
   }
  if (success = 0){
	do ..doHistory(facenum, "Сохранен базовый период за "_base)	   
  }else{
    do ..doHistory(facenum, "Ошибка сохранения базового периода за "_base)
  }
  q success
}

/// Массовое создание базовых периодов для крона
/// writeGo - писать в базу или нет. 0 - нет, 1 - записываем
/// noLog - писать логи или нет. 1 - нет, 0 - записываем
/// facenum - выделить определенный лицевой счет
/// house - выделить дом
/// periodForPO - период не в Horolog, который мы подаем для формирования базового периода за этот месяц
ClassMethod MassCreateBasePeriod(
	facenum As %String = "",
	house As %String = "",
	periodForPO As %Date = "",
	writeGo As %Integer = 0,
	noLog As %Integer = 1) As %Boolean
{
   //q ""
   s bperiod = $zd($H, 4)
   
   if (periodForPO '= ""){
    s bperiod = periodForPO
   }
   
   do ..doHistory(facenum, "Запуск массового формирования базового периода ")
   s voCharges = ##class(%ZEN.proxyObject).%New()
   s voCharges.cold = 0, voCharges.hot = 0
    
  /// берем базовый - ТУТ -1 для 2017 года
  s td = $System.SQL.DATEPART("YYYY", $zdh(bperiod, 4))
  // - 1
  /// определяем месяц
  s mm = $System.SQL.DATEPART("MM", $zdh(bperiod, 4))
  if (+mm < 9){
	s mm = "0"_mm  
  }
  
  ///дата конца заданного сравниваемого периода
  s td2 = $SYSTEM.SQL.LASTDAY($zdh(bperiod, 4))
    
  s tdb1 = "01/"_mm_"/"_td, tdb2 = $zd(td2, 4)
  
  if (noLog = 1){
   do ..doLog("tdb1="_tdb1_", tdb2="_tdb2)
  }
  s start = "01/"_mm_"/"_td, end = $zd(td2, 4)
  
  s warmDog = 0
  
  s period = $zdh(tdb1, 4)
  
  s SQLText = "select distinct facenum from Contracts.EPhDogovor "
  s SQLText = SQLText_" where Type = 2 and BDate <= to_date('"_tdb1_"', 'dd/mm/yyyy') and EDate >= to_date('"_tdb2_"','dd/mm/yyyy') "
  
  if (facenum '= ""){
   s SQLText = SQLText_" and facenum = '"_facenum_"'"
  }
  
  if (house '= ""){
   s SQLText = SQLText_" and  Address->House= "_house
  }

  s SQLQuery = ##class(%SQL.Statement).%New()
  d SQLQuery.%Prepare(SQLText)
  s DataRow = SQLQuery.%Execute()	
  
  do ..doLog("====Начало работы метода по созданию базового периода(массовое)- "_$zdt($H)_"======")
  
  while DataRow.%Next(){
   
   s facenum = DataRow.facenum
   //if (noLog = 1){
    do ..doLog("Лицевой счет:  "_facenum)
   //}
    /// берем все услуги по договору
   s SQLQuery = ##class(%SQL.Statement).%New()
   s SQLChildText = "select id, Type from Contracts.EPhDogovor "
                    _"where facenum = '"_facenum_"' "
                    _"and BDate <= to_date('"_tdb1_"', 'dd/mm/yyyy') and EDate >= to_date('"_tdb2_"','dd/mm/yyyy') "
                    _"order by Type"
   d SQLQuery.%Prepare(SQLChildText)
   //w SQLChildText
   s DataRowChild = SQLQuery.%Execute()
   s dg = ..getDgByFacenum(facenum)
   s houseid = ##class(Contracts.EPhDogovor).HouseDg(dg)
   s SchemaGV = ##class(Address.EHouseDesc).getGVSchemeByHouse(houseid)
   
   s currentItem = 0
   
   if (noLog = 1){
    do ..doLog("Схема ГВС для дома: "_SchemaGV)
   }
   
   while DataRowChild.%Next(){
    /// по продукциям
    /// проверяем, есть ли вообще такая продукция открытая за период
    if (..isTypeExists(facenum, DataRowChild.Type, tdb1, tdb2) = 0){
	 continue   
    }
    
    s row = ##class(%ZEN.proxyObject).%New()
    s pd = DataRowChild.Type, dg = DataRowChild.id
    
    s item = ##class(Charges.EServKind).GetRootItem(pd)
	if (noLog = 1){
	 do ..doLog("Главная услуга для "_pd_":  "_item)
	}
		
	s curr = ..getFlatCharges(facenum, item, $zdh(tdb1, 4))
	
	s tdb2 = $lg(curr, 3)
	
	if (+tdb2 = 0){
	 s tdb2	= $zd(period, 4)	
	}
	if (noLog = 1){
	 do ..doLog("tdb2 = "_tdb2)
	}
    s sqhum = ##class(Calc.HistoryParamOfNach).CountJilSq(dg, $zdh(tdb1, 4), item)
    /// если получаем в истории начислений несовпадение по периодам(если эти коровы заведут неверные даты задним числом)
    /// то берем стандартным методом
    s testhum = $lfs(sqhum, "^")
    if ((+$lg(testhum, 1) = 0) || (+$lg(testhum, 2) = 0)){
     
     s countChangeNSI = ..ifChangeNSI(dg, $zdh(tdb1, 4), tdb2)
     s sqhum = ##class(Contracts.EPhDogovor).CountJilSq(dg, $zdh(tdb1, 4), $zdh(tdb1, 4))
    
	 if (+countChangeNSI > 1){
	  s sqhum = ##class(Contracts.EPhDogovor).CountJilSq(dg, $zdh(start, 4), $zdh(end, 4))   
     }    
     
    }
    s sqhum = $lfs(sqhum, "^")
    s humans = $lg(sqhum, 1), kvm = $lg(sqhum, 2)
    
    if (noLog = 1){
     do ..doLog("Дата для определения численности и площади:  "_$zd(tdb2, 4)_" : "_$zd(tdb2, 4))
    }
		
	if (noLog = 1){
	 do ..doLog("Услуга = "_item)
	 do ..doLog("Договор = "_dg)
	}
	
	s row.vpotr = $lg(curr, 1)
	
	/// сохраняем промежуточный элемент --- fix для тарифа, где может быть гвс на хвс
	s currentItem = item
    
	if (item = 131){
	 /// ХВ
	 s voCharges.cold = row.vpotr
	}
	if (item = 11){
	 s warmDog = dg	
	}
	
	if (item = 91){
	 /// Для теплоносителя
	 s voCharges.hot = row.vpotr
	 
	 s tcurr = ..getFlatCharges(facenum, 98, $zdh(tdb1, 4))
	 s row.vpotr = row.vpotr + $lg(tcurr, 1)
	 kill tcurr
	 
	 s tcurr = ..getFlatCharges(facenum, 133, $zdh(tdb1, 4))

	 if (+$lg(tcurr, 2) '= 0){
	  s curr = tcurr
	  s currentItem = 133
	 }
	 s row.vpotr = row.vpotr + $lg(tcurr, 1)
	 kill tcurr
	}
	
	s row.summ = $lg(curr, 2)

	if (item = 141){
	 s tcurr = ..getFlatCharges(facenum, 144, $zdh(tdb1, 4))
	 if (+$lg(tcurr, 2) '= 0){
	  s row.summ = row.summ + $lg(tcurr, 2)
	 }
	 if (+$lg(tcurr, 1) '= 0){
	  s row.vpotr = row.vpotr + $lg(tcurr, 1)
	 }
	 kill tcurr
	
	 s tcurr = ..getFlatCharges(facenum, 143, $zdh(tdb1, 4))
	  if (+$lg(tcurr, 2) '= 0){
	  s row.summ = row.summ + $lg(tcurr, 2)
	 }
	 if (+$lg(tcurr, 1) '= 0){
	  s row.vpotr = row.vpotr + $lg(tcurr, 1)
	 }
	 
	 kill tcurr
	 
	}
	
	s row.square   = kvm
	if (noLog = 1){
	 do ..doLog("Площадь = "_kvm)
	}
	
	s row.humans   = humans
	
	if (noLog = 1){
	 do ..doLog("Людей = "_humans)
	 do ..doLog("Текущий Item = "_currentItem)
	}
	s row.contract = dg
	s row.facenum = facenum
	s row.periodType = "BASE"
	
	s row.item =  currentItem  
	
	s row.bperiod = $zdh(tdb1, 4) //testbperiod //
	s row.prod = pd
	
	s ctax = ..GetCurTax(currentItem, tdb1)
	
	if (noLog = 1){
	 do ..doLog("Предполагаемый тариф = "_$lg(ctax, 2))
	}
	
	s row.unit = $lg(ctax, 3)
    if (noLog = 1){
     do ..doLog("Ед. изм = "_row.unit)
    }
    s row.tax = $lg(ctax, 2)
    
    if (item = 11){
	 /// custom tar
	 s row.tax = ##class(Tarifs.EEBTarifs).SeleTax(row.contract, row.item, $zdh(tdb1, 4), .taxunitb, .taxprodb)   
    }
    
    if (noLog = 1){
     do ..doLog("Тариф = "_row.tax)
     do ..doLog("Потребление = "_row.vpotr)
     do ..doLog("Сумма = "_$lg(curr, 1))
     //zw curr
    }	
    
    
    if ((pd = 9) || (pd = 13) || (pd = 14) || (pd = 1) || (pd = 15)){
	    s row.vnorm = humans
	   }else{
		s row.vnorm = kvm
	   }
    
    s row.servicetype = $lg(curr, 4)
    s row.item = item
    
    /// определенный момент для фиктивного тарифа
    if ((+row.summ = 0) && (+row.vpotr '= 0)){
	 s row.tax = 0   
    }
    
    if (noLog = 1){
     do ..doLog("Тип начислений = "_row.servicetype)
     do ..doLog("----------------------------")
    }
    if (row.servicetype = 0){ 
     s row.servicetype = 2
    }
    
    if (writeGo = 1){ 
     /// поменять на реальный период
     &sql(delete from Charges.DropFinance  
    	      where facenum = :facenum and BPeriod = :period and periodType = 'BASE' and Item = :item)
     do ..writeObjectRow(row, "BASE")
    }
    kill row, SQLQuery
   }  
    
    /// для 95 - ГВС: тепловая энергия
    ////  
    /// проверяем, есть ли на лицевом счете ГВС
    //s gv = 0
    s gv = ..isTypeExists(facenum, 9, tdb1, tdb2)
	    
    if (+gv '= 0){
     s item = 95, row = ##class(%ZEN.proxyObject).%New()
     s curr = ..getFlatCharges(facenum, item, $zdh(tdb1, 4))
	
	s dg = 0
	&sql(select ID into :dg from Contracts.EPhDogovor where facenum = :facenum 
	     and Type = 9 
	     and BDate <= to_date(:tdb1, 'dd/mm/yyyy') 
	     and EDate >= to_date(:tdb2,'dd/mm/yyyy'))
	
	s row.vpotr = $lg(curr, 1)
	
	if (+row.potr = 0){
	s row.item =  item
	if (noLog = 1){
	 do ..doLog("Услуга = "_item)
	}
	s row.square   = kvm
	if (noLog = 1){
	 do ..doLog("Площадь = "_kvm)
	}
	s row.humans   = humans
	if (noLog = 1){
	 do ..doLog("Людей = "_humans)
	}
	s row.contract = dg
	s row.facenum = facenum
	s row.periodType = "BASE"
	
	s row.bperiod = $zdh(tdb1, 4) 
	s row.prod = 9
	/// в поиске тарифа участвует дата, услуга и схема ГВ
	s ctax = ..GetCurTax(row.item, tdb1,,0)
	//zw ctax
	s row.unit = $lg(ctax, 3)	
    if (noLog = 1){
     do ..doLog("Ед. изм = "_row.unit)
    }
    
    s row.tax = ##class(Tarifs.EEBTarifs).SeleTax(dg, item, $zdh(tdb1, 4), .taxunitb, .taxprodb)
    if (noLog = 1){ 
     do ..doLog("Тариф = "_row.tax)
    }
    s row.summ = row.vpotr * row.tax 
    if (noLog = 1){ 
     do ..doLog("Потребление = "_row.vpotr)
    }
    
    if ((pd = 9) || (pd = 13) || (pd = 14) || (pd = 1) || (pd = 15)){
	    s row.vnorm = humans
	   }else{
		s row.vnorm = kvm
	   }
	 
	s row.servicetype = $lg(curr, 4)   
	if (noLog = 1){
	 do ..doLog("Тип начислений = "_row.servicetype)
	 do ..doLog("----------------------------")
	}
	
    if (+row.servicetype = 0){
	  s row.servicetype = 2
	}
    if (writeGo = 1){ 
     /// поменять на реальный период
     &sql(delete from Charges.DropFinance  
    	      where facenum = :facenum and BPeriod = :period and periodType = 'BASE' and Item = :item)
     do ..writeObjectRow(row, "BASE")
    }
    kill row
	}
	
   }
	
    //// ЭЭ
     s normparts = ##class(Normativs.NormativsGas).GetActual(tdb1)
	 /// для минимальной соцнормы э/э
	 s normee = $lg(normparts, 2)
	 /// для расчетной соцнормы э/э
	 s normsne = $lg(normparts, 4)
   
     s row = ##class(%ZEN.proxyObject).%New()
    
     s row.item = 1002
	 /// определяем, есть ли на доме газ
	 s gasBlago = ##class(Address.EHouseDesc).getGasBlagoByHouse(houseid)
	 if (gasBlago = ""){
	  /// значит для эл плит
	  s el = 1	 
	 }else{
	  s el = 0	 
	 }
	 s Prod = 1, vptree = 0
		
	 if (Prod = 1){
		 /// берем количество человек для текущего периода, из этого определяем необходимую соц. норму
		 &sql(select VPotr, Summ, Tax into :vptree, :vsummee, :veetax from Charges.DropFinance 
	      where facenum = :facenum and Prod = :Prod and BPeriod = to_date(:tdb1, 'dd/mm/yyyy') and serviceType = 1)
		 if (+vptree = 0){
		 if (humans * normsne < normee){
		  if (noLog = 1){
		   do ..doLog("humans * normsne < normee: "_normee)
		  }
		  s row.vpotr = normee
		 }else{
		 // соцнорма для человека по ээ
	      s row.vpotr = humans * normsne
		 }
		
		 s row.servicetype = 2 /// тип начисления
		 }else{
		  
		  if (humans * normsne < normee){
		  if (normee > vptree){
			s row.vpotr = vptree  
			//do ..doLog("normee > vptree ")
		  }else{
		    s row.vpotr = normee  
		    //do ..doLog("s row.vpotr = normee ")
		  }
		  }else{
		   /// 2 и более человек
		   if (vptree > humans * normsne){
			s row.vpotr = humans * normsne 
			//do ..doLog("vptree > humans * normsne ")
		   }else{
			s row.vpotr = vptree
		   }
			  
		  }
		  //w row.vpotr
		  s row.servicetype = 1 /// тип начисления
		  }
	     
	    }
		 if (noLog = 1){
		  do ..doLog("Услуга = "_row.item_" и период для тарифа: "_tdb1)
		 }
		 s tax = ..GetCurTax(row.item, tdb1, el)

		 s row.unit = $lg(tax, 1)
		 
		 if (noLog = 1){
		  do ..doLog("Ед. изм = "_row.unit)
		 }
		 
		 /// тариф на превышение соц. нормы
		 s taxLRate = $lg(tax, 4)

		s row.tax = taxLRate
	
		s row.square   = kvm
	 	s row.humans   = humans
		s row.contract = 0
		s row.facenum = facenum
		s row.periodType = "BASE"
		s row.vnorm = humans
		s row.bperiod =  period // $zdh(tdb1, 4)
		s row.prod = 1
		
		s row.contract = warmDog
		
	    s row.summ = row.tax * row.vpotr
        if (noLog = 1){
         do ..doLog("Потребление = "_row.vpotr)
        }
        if (+row.vpotr '= 0){
	     	    
        if (writeGo = 1){ 
    	 &sql(delete from Charges.DropFinance  
    	      where facenum = :facenum and BPeriod = :period and periodType = 'BASE' and Item = 1002)
    	 do ..writeObjectRow(row, "BASE")
    	}
    	
    	}
        kill row
        s row = ##class(%ZEN.proxyObject).%New()
        if (noLog = 1){
         do ..doLog("----------------------------") 
        }
        //w "gasblago="_gasBlago, !
        if (+gasBlago '= 0){
	     s Prod = 15, row.item = 1001
	     /// надо проверить, внесены ли показания - расход - факт
	     s vptrgas = 0
	     &sql(select VPotr, Summ, Tax into :vptrgas, :vsummgas, :vgastax from Charges.DropFinance 
	      where facenum = :facenum and Prod = :Prod and BPeriod = :tdb1 and serviceType = 1)
	     /// не внесены
	     if (+vptrgas = 0){
	      s normgas = ..getGasNormbyHouse(houseid, tdb1)
	      s row.vpotr = normgas * humans
   
	      s row.servicetype = 2
	     }else{
		  s row.vpotr = vptrgas
		  s row.servicetype = 1
		 }
	   
		 /// на доме определяем тариф: 			
		 s taxprodc = ..getGasTariffbyHouse(houseid, $zdh(tdb1, 4))
		 s ctax = ..GetCurTax(row.item, tdb1)	
		 s row.tax = taxprodc //$lg(ctax, 2)
	     s row.unit = $lg(ctax, 1) 
	    
	     s row.square   = kvm
	 	 s row.humans   = humans
		 s row.contract = warmDog
		 s row.facenum = facenum
		 s row.periodType = "BASE"
		 
		 s row.vnorm = humans
 		 
 		 s row.bperiod = period //$zdh(tdb1, 4)
		 s row.prod = 15
		
	     s row.summ = row.tax * row.vpotr
      	 if (noLog = 1){
      	  do ..doLog("Услуга = "_row.item)
      	  do ..doLog("Тариф = "_row.tax)
      	  do ..doLog("Ед. измерения = "_row.unit)
      	  do ..doLog("Потребление = "_row.vpotr)
      	 }
	    //if (+row.vpotr '= 0){
	     if (writeGo = 1){ 
    	  &sql(delete from Charges.DropFinance  
    	      where facenum = :facenum and BPeriod = :period and periodType = 'BASE' and Item = 1001)
    	  do ..writeObjectRow(row, "BASE")
	    }
   		
   		//}
	    kill row
	    }


   /// теперь берем первую строку и апдейтим суммой ВД, полученной из текущего периода
 if (writeGo = 1){ 
   s vd = 0
   &sql(select sum(VDSum) into :vd from Charges.DropFinance where facenum = :facenum and BPeriod = :period and periodType is NULL)
   &sql(update Charges.DropFinance 
        set VDSum = :vd 
        where id = (select top 1 id from Charges.DropFinance where 
                   facenum = :facenum and BPeriod = :period and periodType = 'BASE'))	
   if (noLog = 1){
    do ..doLog("Пишем ВД:"_vd_" на ЛС: "_facenum_", период: "_$zd(period, 4)_", сумма: "_vd)
   }
  }
  
  }
 do ..doHistory(facenum, "Окончание массового формирования базового периода ")
 do ..doLog("============ Конец метода автосоздания базового периода "_$zdatetime($H)_" ============ ")
}

/// Метод ставит флаг для периода, что он базовый
ClassMethod setBaseFlag(
	facenum,
	td1) As %Boolean
{
 &sql(update Charges.DropFinance set periodType = 'BASE' where facenum = :facenum and BPeriod = :td1)
}

ClassMethod writeRow(
	list As %List,
	base As %String = "") As %Boolean
{
 //do ..doLog("potr = "_$lg(list, 11))
 s result = 0
 s df = ..%New()
 s df.Unit     =    ##class(Refs.Unit).%OpenId($lg(list, 2)) ///единичка
 s df.BPeriod  =    $lg(list, 3) /// бухпериод
 s df.Contract =    ##class(Contracts.EPhDogovor).%OpenId($lg(list, 4)) /// id договора
 s df.Item     =    $lg(list, 5) 
 s df.Prod     =    $lg(list, 6) /// продукция
 s df.Summ     = 	$lg(list, 7) /// сумма
 s df.Tax      =    $lg(list, 8)  /// тариф
 s df.VDSum    =    $lg(list, 9)
 s df.VNorm    =    $lg(list, 10)
 s df.Vpotr    =    $fn($lg(list, 11), "", 6)
 s df.CDate    =    +$H
 s df.Humans   =    $lg(list, 12)
 s df.Square   =    $lg(list, 13)
 s df.facenum  =    $lg(list, 14)
 /// пользователь, кто пишет
 
 s user = ##class(Auth.SysUser).CheckUser()
 s user = ##class(Auth.SysUser).%OpenId(user)
 //s fio = ##class(Auth.SysUser).GetFullName(user)
 s df.ChangedBy = user
 
 if ($listlength(list) >= 15){
  s df.serviceType  =    $lg(list, 15)  
 }
 
 if (base '= ""){
  s df.periodType = base	 
 }
 
 s rs = df.%Save()
 if (rs){ 
  s result = 1
  do ..doLog("ЛС записан для "_$lg(list, 4)_" "_df.Item_", tax="_df.Tax_"; "_df.facenum_"; humans="_df.Humans_"; Unit="_df.Unit.Name_"; df.Vpotr="_df.Vpotr)
 }else{
   do ..doLog("При записи возникла ошибка для item="_df.Item_", tax="_df.Tax_"; "_df.facenum_"; humans="_df.Humans_"; Unit="_df.Unit.Name)	 
 }
 
 q result
}

ClassMethod MassCalc(
	td1 As %String,
	p1 As %String,
	debug As %Boolean = 0) As %Boolean
{
	
	s param = $lfs(p1, ";")
	//do ..doHistory(facenum, "Запуск массового расчета ВД ")
	do ..doLog("а мы начинаем....")
	s street = $lg(param, 3) /// улица
	s house = $lg(param, 4) /// номер дома
	s region = $lg(param, 2) /// район
	s company = $lg(param, 8) /// компания
	
	s cityes = $lg(param, 13)
	//cwt
	s bperiod = td1
	s cbperiod = $zdh(td1, 4)
	
	/// проверяем какой подается базовый
	
	s currentY = $System.SQL.DATEPART("YYYY", cbperiod)
	s currentM = $System.SQL.DATEPART("MM", cbperiod)
	s kperiod = ##class(Refs.BasePeriod).getActual(currentY, currentM)
	if (kperiod = -1){	
	 s parts = $lfs(..GetPrevYear(bperiod), "^")
 	 s base = $lg(parts, 1)
	}else{
	s base = kperiod	
	}
	
	// если отмечена галочка - включать в расчет нормативников
	s normflag = $lg(param, 12)
	
	
	do ..doLog("------------- Начало массового расчета ВД -----------",,1)
	do ..doLog("Учитывать ли нормативщиков: "_normflag,,1)
	do ..doLog("Входные параметры: "_p1,,1)
	do ..doLog("Дата: "_td1,,1)
	do ..doLog("Города: "_cityes,,1)
	
	/// выбираем все лицевые, у которых есть начисления + есть базовый период + есть начисления факт по газу
	s SQLText = "select * from (select distinct Contract->Facenum as eafacenum from Charges.EChargesA "
 	s SQLText =	SQLText_" where MonthPay = to_date('"_bperiod_"', 'dd/mm/yyyy') "
	/// если задана улица
	if (street '= -1){
	  s SQLText = SQLText_" and Contract->Address->Street = "_street
	 if (house '= -1){
  	  s SQLText = SQLText_" and Contract->Address->House->Num = rtrim(ltrim('"_house_"')) "
	 }
	 
	}
	
	if (cityes '= -1){
	 s city = $replace(cityes, "^", ",")
	  s SQLText = SQLText_" and Contract->Address->City in ("_city_") "	
	}
	/// все те, которые имеют факт ээ
	if (+normflag = 0){
	 s SQLText =	SQLText_" and Contract->facenum in ( select facenum from Charges.DropFinance "
	 s SQLText =	SQLText_" where BPeriod = to_date('"_bperiod_"', 'dd/mm/yyyy') and serviceType = 1 and Item = 1002 ) "
	}
	
	if (+normflag = 1){
	 s SQLText =	SQLText_" and Contract->facenum not in ( select facenum from Charges.DropFinance "
	 s SQLText =	SQLText_" where BPeriod = to_date('"_bperiod_"', 'dd/mm/yyyy') and serviceType = 1 and Item = 1002 ) "
	}
	
	s SQLText =	SQLText_" ) "
	s SQLText =	SQLText_" d where "
  	s SQLText =	SQLText_" eafacenum in (select distinct facenum from Charges.DropFinance "
  	s SQLText =	SQLText_" where BPeriod = to_date('"_base_"', 'dd/mm/yyyy') and periodType = 'BASE') "
    
    s SQLText =	SQLText_" order by 1"
	do ..doLog("Запросик: "_SQLText,,1)
	
	s SQLQuery = ##class(%SQL.Statement).%New()
  	d SQLQuery.%Prepare(SQLText)
    s DataRow = SQLQuery.%Execute()    	
  	 	 
 	while DataRow.%Next(){
     s facenum = DataRow.eafacenum
	 
 	 do ..doLog("Расчет ЛС: "_facenum_" ",,0)
	 s status = ..CalcCurrentFix(facenum, cbperiod, 0)
	 if (status = 1){
	  do ..doLog("ЛС рассчитан успешно: "_facenum,,1)
	 }else{
	  do ..doLog("ЛС рассчитан с ошибкой: "_facenum,,1)	 
	 }
 
	 &sql(declare dl cursor for 
	      select t.* from (
	      select distinct month(ToDataB) mnt, year(ToDataB) ye 
	      from Charges.EChargesA 
	      where Contract->facenum = :facenum and Type = 40 and MonthPay = :cbperiod
	      union
	      select distinct month(BPeriod) mnt, year(BPeriod) ye from Charges.DropFinance
		  where facenum = :facenum and month(CDate) = month(:cbperiod) 
		  and year(CDate) = year(:cbperiod) and serviceType = 1 and Item in (1001, 1002)
		  and CDate <> BPeriod 
		  ) t
		  order by 1
	      )

	 &sql(open dl)
	 for{
	 &sql(fetch dl into :m, :y)
	 if (SQLCODE){
	  q	 
	 }
	 if (+m < 10){
	  s m = "0"_m	 
	 }
 	
	  do ..MassRecalc(facenum, y_"/"_m, y_"/"_m, 1)
	 }
	}
	do ..doHistory(facenum, "Окончание массового расчета ВД ")
 q 0
}

/// этап 2: берем лицевой счет
/// смотрим были ли перерасчеты + выделяем месяцы и пересчитываем по ним ВД
/// Перерасчет за прошлые периоды
/// Обязательно использовать: дату подавать в виде "год/месяц", т.е. MassRecalc(1632126, "2018/10", "2018/10", 1)
ClassMethod MassRecalc(
	facenum As %String,
	period1 As %String,
	period2 As %String,
	toCalc As %Integer = 0) As %ListOfObjects
{
	do ..doHistory(facenum, "Перерасчет ЛС по ВД за прошлые периоды: "_period1_" : "_period2_", Запись: "_toCalc)
	/// создаем объект и начинаем рассчитывать
	set data = ##class(%ListOfObjects).%New()
	s pr = $lfs(period1, "/")	
	s prt = $lfs(period2, "/")	
	do ..doLog("----Массовый перерасчет------ для ЛС:  "_facenum,,1)
	/// проверим, есть ли базовый период
	/// год начало даты
	s td     = +$lg(pr, 1)
	// год конец даты
	s tdper2 = +$lg(prt, 1)
	/// по годам
	s firstTime = 0
	for currentYear = td:1:tdper2{
	
	do ..doLog("Идем по году:  "_currentYear,,1)
	
	s tdb1   = "01/12/"_(currentYear - 1), tdb2 = "31/12/"_(currentYear - 1)
	s currPeriod   = "01/12/"_currentYear
	
	if (td = tdper2){ /// если в пределах года
	  s m1 = +$lg(pr, 2)
	  s m2 = +$lg(prt, 2)
	}else{
	 /// разные года	
	  if (firstTime = 0){
		s m1 = +$lg(pr, 2)
	    s m2 = 12		  
	    s firstTime = 1
	  }else{
		s m1 = 1
	    s m2 = +$lg(prt, 2)		  
	  }
	  	
	}

	do ..doLog("Базовый период m1:  "_tdb1_"; m2 = "_tdb2,,1)

	s prev = tdb1 //$lfs(..GetPrevYear(tdb2), "^")
	
	//s basevd = ..GetSumBaseVD($zdh($lg(prev, 1), 4), facenum)
	s basevd = ..GetSumBaseVD($zdh(prev, 4), facenum)
	do ..doLog("ВД по базовому периоду:  "_basevd,,1)
	s dgID = ..getDgByFacenum(facenum)
	do ..doLog("Договор:  "_dgID,,1)
	
	s pd = ##class(Contracts.EPhDogovor).getProdDg(dgID)
	s item = ##class(Charges.EServKind).GetRootItem(pd)
	
	do ..doLog("prod="_pd_"; item="_item,,1)
	/// здесь берется текущий период
	s forFixedMonth = "01/"_currentYear
	do ..doLog("forfixedmonth="_forFixedMonth_", currPeriod = "_currPeriod,,1)
	
	s monthFixed = ..isFixed(facenum, currPeriod)
	
	do ..doLog("monthFixed = "_monthFixed,,1)
	
	if (monthFixed '= 1){
	 //q ///"{error:1}"
	// continue
	}
	
	/// берем даты
	do ..doLog("Месяцы для работы: "_m1_":"_m2,,1)
	
	for i=m1:1:m2 {
	 /// считаем лицевой по месяцам
	 s vr = ##class(%ZEN.proxyObject).%New()
	 s vr.facenum = facenum
	 s month = i
	 if (i < 10){
	   s month = "0"_i
	 }

	 s vr.period = month_"/"_currentYear
	 do ..doLog("в цикле по месяцам vr.period = "_vr.period)
	 s lastday = $SYSTEM.SQL.LASTDAY(currentYear_"-"_month_"-01")
	 
	 s vr.existsVD = $fn(..getFactVDbyLS(facenum,$zdh("01/"_vr.period, 4),lastday), "", 2)
	 
	 do ..doLog("vr.existsVD = "_vr.existsVD,,1) 	 	 
	 
	 s vdstring = ..getFaceVD(facenum, "01/"_vr.period, 0)
	 s vdlist = ..Parce(vdstring)
	 s (basesum, currsum, pindex) = 0
	 
	 for k=1:1:$ll(vdlist){
	  s vl = $list(vdlist, k)
	  s basesum = basesum + $lg(vl, 6)
	  s currsum = currsum + $lg(vl, 10)
	  do ..doLog("Сумма по услугам:  basesum = "_basesum_"currsum = "_currsum,,1) 
	 }
	 do ..doLog("Сумма по услугам итого:  basesum = "_basesum_"currsum = "_currsum,,1) 
	 
	 s pindex =  ##class(Refs.EndPointIndex).GetActual("01/"_vr.period)
 	 do ..doLog("period_index:  "_"01/"_vr.period,,1)
 	 /// считаем
	 do ..doLog("period:  "_vr.period,,1)
	 s delta = (basesum - basevd)
	 do ..doLog("delta = (basesum - basevd):  "_basesum_" - "_basevd,,1)
	 s delta = delta + ((delta/100) * pindex)
 	 do ..doLog("pindex =  "_pindex,,1)
 	 s vd = currsum - delta
	 s vr.calculated = $fn(vd, "", 2)
	 
	 /// считаем вд абстрактные	
	 if (vr.calculated < 0){
	  s vr.calculated = 0	 
	 }
	 do ..doLog("Посчитанная текущая:  "_vr.calculated,,1)
	 do ..doLog("Посчитанные сущ-е ВД:  "_vr.existsVD,,1)
	 
	 s vr.summ = $fn((vr.calculated - vr.existsVD), "", 2)
	 do ..doLog("Посчитали сумму:  "_vr.summ,,1)
	 /// при втором запросе, который отправляется после предварительного расчета
	 //w "vr = "_vr.summ_"; toCalc = "_toCalc
	 if ((toCalc = 1) && (+vr.summ '= 0)){
	  // исправил для minusCorrection
	  // смысл minusCorrection - использование минусов для сторнирования ВД 
	  // обычно режется минусы для 0 и убирает запись в базу. Этот флаг дает запись
	  do ..CalcCurrentFix(facenum, $zdh("01/"_vr.period, 4), 0,,1)
	 }
	 do data.Insert(vr)
	}
	
	}
	do ..doLog("--------------------MassRecalc----------------------",,1)
	q data
}

/// проверяет, зафиксирован ли базовый период - имеется ли рассчитанный период декабрь.
/// Возвращает 1 или 0. 0 - не зафиксирован
/// в параметры передается лицевой счет и дата, от которой считается базовая дата
ClassMethod isFixed(
	facenum As %String,
	td1 As %Date) As %Boolean
{
	s parts = $lfs(..GetPrevYear($zdh(td1, 4)), "^")
	
	s base = $zdh($lg(parts, 1), 4)
	//do ..doLog("Базовый период: parts1= "_$lg(parts, 1),,1)
	s result = 0
	&sql(select count(ID) into :ncounter from Charges.DropFinance where BPeriod = :base and facenum = :facenum and periodType = 'BASE')
	 if (+ncounter '= 0){ 
	  s result = 1
	 }
	q result
}

ClassMethod Parce(data As %String) As %Library.List
{
 s rows = $lfs(data, "&")
 s (service, list) = ""
 for i=1:1:$ll(rows){
  s u = $lg(rows, i)
  s service =  $lfs(u, "^") 
  if ($ll(service) = 0) continue
  s list = list_$lb($lb($lg(service, 1), $lg(service, 2), $lg(service, 3), $lg(service, 4), $lg(service, 5), $lg(service, 6), $lg(service, 7), $lg(service, 8), $lg(service, 9), $lg(service, 10), $lg(service, 11), $lg(service, 12), $lg(service, 13), $lg(service, 14), $lg(service, 15), $lg(service, 16), $lg(service, 17)))
 }
 q list
}

/// Расчет по лицевому счету
ClassMethod FaceCalc(
	facenum As %String,
	td1 As %Library.Date,
	debug As %Integer = 0) As %String
{
	s tres = ""
	&sql(declare citem cursor for 
	     select Contract->facenum as facenum, Item into :facenum, :item
	     from Charges.EChargesA 
	     where Contract->facenum =  :facenum and Contract->status = 0
 	     group by 1, Item)
 	     &sql(open citem)
	  for{
	     &sql(fetch citem) 
	     q:SQLCODE
			 s res = ..Calculate(0, td1, debug, item, facenum)
			 if (res '= -1){
			  s tres = tres_res
			 }
 		}
	&sql(close citem)
	
	/// дополнительно: здесь определяем тип дома. Есть ли газ, плита, ээ
	/// смотрим, были ли в базовом периоде газ и ээ
	/// считаем для текущего по нормативу, из ТЗ и добавляем в общую сетку
	
	w:debug=1 tres, !
	q tres
}

/// определение для ВД - изменились ли виды начисления за периоды по услуге
/// 0 - виды начислений совпадают, 1 - был норматив стал ипу, 2 - был ипу стал норматив
/// Добавлено 06.07.2018 Балуков
ClassMethod getTypesByService(
	dgID As %String,
	Item As %Integer,
	bperiod1 As %Library.Date,
	bperiod2 As %Library.Date) As %Integer
{
		s (res1, res2) = "", res = 0, bperiod1 = $zdh(bperiod1, 4), bperiod2 = $zdh(bperiod2, 4)
		&sql(declare cr1 cursor for select ServiceType into :serviceType1 from charges.EChargesA 
				 where Item = :Item 
				 and ServiceType <> 3
				 and MonthPay=:bperiod1
				 and contract->ID = :dgID 
				 and status=0
				 and summ <> 0 
				 group by ServiceType order by 1)
		&sql(open cr1)
		for
		{		
				&sql(fetch cr1)
				q:SQLCODE 
				s res1 = res1_$lb(serviceType1)
		}
		&sql(close cr1)		 
		&sql(declare cr2 cursor for select ServiceType into :serviceType2 
				 from charges.EChargesA 
				 where Item = :Item and ServiceType <> 3
				 and MonthPay=:bperiod2 and Type not in (4,10,15) and contract->ID = :dgID and status=0
				 and summ <> 0 
				 group by ServiceType order by 1)
		&sql(open cr2)
		for
		{		
				&sql(fetch cr2)
				q:SQLCODE 
				s res2=res2_$lb(serviceType2)
		}		 
		&sql(close cr2)
		if ($ll(res1) > $ll(res2)){
		 for i=1:1:$ll(res1){   s n = $list(res1, i)
		  if ($lf(res2, n)'=0){ s last = n, next = $lg(res2, i)
		   if ((last = 1) && (next = 2)){ s res = last  }
		   elseif ((last = 2) && (next = 1)){s res = next}
		   return res
		  }
		 } 				
		}elseif($ll(res1) < $ll(res2)){
		 for i=1:1:$ll(res2){ s n = $list(res2, i)
		  if ($lf(res1, n)'=0){ s last = n, next = $lg(res1, i)
		   if ((last = 1) && (next = 2)){ s res = last  }
		   elseif ((last = 2) && (next = 1)){s res = next}
		  return res
		   
		  }
		 } 	
		}elseif($ll(res1) = $ll(res2)){ if ($lg(res1, 1) = $lg(res2, 1)){s res = 0}
		 elseif(($lg(res1, 1) = 1) && ($lg(res2, 1) = 2)){ s res = 1}
		 elseif(($lg(res1, 1) = 2) && ($lg(res2, 1) = 1)){ s res = 2}
		}

		q res
}

ClassMethod getProdByItem(Item As %Integer) As %Integer
{
	  s prod = 0
	  &sql(select ProdKind->Code into :prod from Charges.EServKind where Code = :Item)
	  q prod
}

/// метод берет и выбирает по услуге , лицевому, периоду - количество человек с базового периода
ClassMethod getOldHumans(
	facenum As %String,
	Item As %Integer,
	td1 As %Date) As %Integer
{
	s old = 0
	&sql(select Humans into :old 
	     from Charges.DropFinance where facenum = :facenum and Item = :Item and BPeriod = :td1 and periodType = 'BASE')
	q old
}

ClassMethod getOldTax(
	facenum As %String,
	Item As %Integer,
	td1 As %Date) As %Integer
{
	s old = 0
	&sql(select Tax into :old 
	     from Charges.DropFinance where facenum = :facenum and Item = :Item and BPeriod = :td1 and periodType = 'BASE')
	q old
}

/// метод берет и выбирает по услуге , лицевому, периоду - сумму помещений площадь с базового периода
ClassMethod getOldSquare(
	facenum As %String,
	Item As %Integer,
	td1 As %Date) As %Integer
{
	s old = 0
	&sql(select Square into :old 
	     from Charges.DropFinance where facenum = :facenum and Item = :Item and BPeriod = :td1 and periodType = 'BASE')
	q old
}

ClassMethod GetPrevYear(td1)
{
 s td = $System.SQL.DATEPART("YYYY", td1) - 1
 q "01/12/"_td_"^"_"31/12/"_td
}

/// isBasesTarif - служит только для определения тарифа по ээ
/// 0 - тариф для газовых плит, 1 - тариф для ээ плит
ClassMethod GetCurTax(
	item As %Integer,
	td1 As %Date,
	isBasesTarif As %Integer = "",
	SchemeGVS As %Integer = 0,
	isCalcTP As %Integer = 0,
	debug As %Integer = 0) As %List
{
     s (UnitT, CurT, UnitTProd, id, curTLRate) = 0
	 
	 /// находим id
	 s SQLText = "select ID, UnitT,CurT,UnitTProd from Tarifs.EEBTarifs where item->code="_item	 
	 if (isBasesTarif '= ""){
	  s SQLText = SQLText_" and isBasesTarif = "_isBasesTarif
	 }
	 if (SchemeGVS '= 0){
	  s SQLText = SQLText_" and SxemaGVS = "_SchemeGVS
	 }
	 
	 if (isCalcTP '= 0){
	  s SQLText = SQLText_" and isCalcTP= "_isCalcTP
	 }
	 if (debug = 1){
	  w SQLText
	 }
	 
	 s SQLQuery = ##class(%SQL.Statement).%New()
  	 d SQLQuery.%Prepare(SQLText)
     s DataRow = SQLQuery.%Execute()    	
  	
  	while DataRow.%Next(){
     s id = DataRow.ID, UnitT = DataRow.UnitT, CurT = DataRow.CurT, UnitTProd = DataRow.UnitTProd
  	}

	 if (isBasesTarif = ""){
	   s tr =  ##class(Tarifs.EEBTarifs).GCurTarifN($zdh(td1, 4), id)
	   s tr = $lfs(tr, "^")
	   s CurT = $lg(tr, 1)
	 }else{
	  /// здесь же определяем тариф превышения из истории
	  s lst = $lfs(##class(Tarifs.EEBTarifs).GCurTarifN($zdh(td1, 4), id), "^")
	  s curTLRate = $lg(lst, 1)
	 }
	 q $lb(UnitT,CurT,UnitTProd, curTLRate)
}

/// изменяет все ЛС в DropFinance при смене ЛС
ClassMethod SwapFacenum(
	dog As %String = "",
	oldFacenum As %String = "",
	newFacenum As %String = "") As %Boolean
{
	if ((oldFacenum '= "") && (newFacenum '= "") || (dog '= "")){
	 
	 s SQLQuery = ##class(%SQL.Statement).%New()
	 s prodText = ""
	 if (dog '= ""){
	  s pd = ##class(Contracts.EPhDogovor).getProdDg(dog)
	  if (pd = 2){
		s prodText = " and Prod in (1, 2, 15)"
	  }else{
	   s prodText = " and Prod = "_pd
	  }
	 }else{
	  s pd = "все"	 
	 }
	 s SQLText = "update Charges.DropFinance set Facenum = '"_newFacenum_"' where Facenum = '"_oldFacenum_"' "_prodText
	 //w SQLText
	 d SQLQuery.%Prepare(SQLText)
     s DataRow = SQLQuery.%Execute()    	
	 if (+DataRow.SQLCODE = 0){
	  do ..doHistory(oldFacenum, "Изменен ЛС с "_oldFacenum_" на "_newFacenum_"("_pd_")")	 
	 }else{
	  do ..doHistory(oldFacenum, "При смене ЛС с "_oldFacenum_" на "_newFacenum_" произошла ошибка")	 
	 }
	}
 q 0
}

/// Рассчитывает параметры начислений для выпадающих доходов
/// На входе код договора, дата, отладка
/// На выходе (Обьем, Тариф, Сумма начисления) - за базовый (Обьем, Тариф, Сумма начисления) - за текущий месяц
ClassMethod Calculate(
	dgID As %Library.String,
	td1 As %Library.Date,
	debug As %Boolean = 0,
	Item As %Integer = 0,
	facenum As %String = "") As %String
{
	if ((+dgID = 0) && (facenum '= "")){
	 s Prod = ..getProdByItem(Item)
	 s dgID = ..getDgByFacenum(facenum)
	}else{
	 s Prod = ##class(Contracts.EPhDogovor).getProdDg(dgID)	
	}
	s servType = 1
	
	w:debug=1 "=== Для договора "_dgID_" ===", !
	w:debug=1 "=== Код продукции "_Prod_" ===", !
	w:debug=1 "=== Услуга "_Item_" ===", !
	
	s currentY = $System.SQL.DATEPART("YYYY", $zdh(td1, 4))
	s currentM = $System.SQL.DATEPART("MM", $zdh(td1, 4))
	
	// проверяем, включена ли галка - включать статью в возмещение
	s act = ##class(Charges.EProdKind).isActualDropFin(Prod)
	
	  if (act = 0){
	    w:debug=1 "Вид продукции имеет отрицательный флаг расчета по ВД("_Prod_")", ! 
	    q -1
	  }else{
		w:debug=1 "Вид продукции активен для расчета", !
	  }
	
	s countHouseOwners = ##class(Contracts.ExtraOptionsDogovor).GetCountHoumewners(facenum)
	
	w:debug=1 "Количество собственников: "_countHouseOwners, !
	
	/// проверяем, можно ли считать по нормативу данный вид продукции
	/// получаем список услуг
	
	s (humans, kvm, s, baseipu, basenorm, currtaxa, frontV) = 0
	// Базовый период
	
	/// проверяем из справочника - есть ли настройка какой брать базовый. Если нет - дефолтный вариант
	s basepart = ##class(Refs.BasePeriod).getActual(currentY, currentM)
	
	s td2 = $SYSTEM.SQL.LASTDAY($zdh(td1, 4))
	
	if (basepart = -1){
	 s td = $System.SQL.DATEPART("YYYY", $zdh(td1, 4)) - 1
	 s tdb1 = "01"_"/12/"_td, tdb2 = "31"_"/12/"_td
	///дата конца заданного сравниваемого периода
	}else{
	  s td = $System.SQL.DATEPART("YYYY", $zdh(basepart, 4))
	  s tdb1 = basepart, tdb2 = $SYSTEM.SQL.LASTDAY($zdh(tdb1, 4))
	}
	
	w:debug=1 "Базовый период для текущего : "_tdb1, !
	
	s sqhum = ##class(Contracts.EPhDogovor).CountJilSq(dgID, $zdh(td1, 4), td2, 0)
	
	w:debug=1 "Начало сравниваемого периода: "_td1, !
	w:debug=1 "Конец сравниваемого периода: "_td2, !
	
	s sqhum = $lfs(sqhum, "^")
	s humans = $lg(sqhum, 1), kvm = $lg(sqhum, 2) 
	
	/// заменяем количество людей на количество собственников, если кол-во людей = 0 
	if (+humans <= 0){
	 s humans = +countHouseOwners
	}
	//w humans
	if (+humans <= 0){
	 s humans = 1
	}
	
	s houseid = ##class(Contracts.EPhDogovor).HouseDg(dgID)

	s SchemaGV = ##class(Address.EHouseDesc).getGVSchemeByHouse(houseid)
	
	s (vptrgas, vsummgas, vgastax, vptree, vsummee, veetax) = 0
		
	w:debug=1 "Определенный договор: "_dgID, !
	
	s oldhumans = +..getOldHumans(facenum, Item, $zdh(tdb1, 4))
	w:debug=1 "oldhumans = "_oldhumans, !
	/// если количество человек в текущем превышает количество в базовом, то берем количество человек базового
	s fronthumans = humans
	
	if (humans > oldhumans){
	  s humans = oldhumans
	}
		
	w:debug=1 "людей: "_humans, !
	w:debug=1 "людей для фронта: "_fronthumans, !
	
	// Общая площадь помещения
	w:debug=1 "площадь жилья: "_kvm, !
	
	/// базовые: вид услуги, измерение, показатель, объем, тариф, сумма начисления
	s (baselist, baseizm, taxunitc) = ""
	s (basep, baseV, baseTax, baseSum, V) = 0
	
	/// нормативы для ээ и газа
	 s normparts = ##class(Normativs.NormativsGas).GetActual(td1)
	 /// для минимальной соцнормы э/э
	 s normee = $lg(normparts, 2)
	 /// для расчетной соцнормы э/э
	 s normsne = $lg(normparts, 4)
	 w:debug=1 "Норматив для э/э: "_normee, !
	 s normgas = $lg(normparts, 1) 
	 w:debug=1 "Норматив на газ: "_normgas, !
	 
	 // коэффициент предельного индекса
	 s koeff = ##class(Refs.EndPointIndex).GetActual(td1)

	///stype - 1 - счетчик, 2 - норматив, 3 - ОДН
	
     s (Vbase, SumBase, Vcurrent, SumCurrent) = 0
     s value = Item 
     s calcNorm = ##class(Charges.EServKind).isCalcNorm(Prod)
		
	 if (calcNorm = 1){
		w:debug=1 "Услугу можно считать по нормативу", !
	 }
	 else{
		w:debug=1 "Услугу НЕЛЬЗЯ считать по нормативу", !
	 }	
        // разбиваем по статьям начисления
     s l = ##class(Charges.EChargesA).getChargesByService(facenum, value, $zdh(tdb1, 4))
                  
         /// название услуги 
	 s uname = ##class(Charges.EServKind).GetName(value)
	 w:debug=1 "Название услуги: "_uname_" код: "_value, !
         
     if ($ll(l) = 0){
	  /// если не было начислений, то определяем исходя из записанных фиксированных данных 
	   w:debug=1 "Начислений нет", !
	   s vn = ..getBaseFixed(dgID, $zdh(tdb1, 4), value)
	   if (debug=1){ 
	    zw vn
	   }
	  } 
         /// Определяем, была ли смена типа начисления
         s changeflag = ..getTypesByService(dgID, value, tdb1, td1)
         w:debug=1 "Смена типа начисления: "_changeflag, !
         
         for k=1:1:$ll(l){ /// по типам
	     s row = $list(l, k)
	     s servType = $lg(row, 1) /// тип начисления
		 
		 w:debug=1 "Тип начислений базового на ",tdb1,": "_servType_", Объем: "_$lg(row, 3)_", Денег: "_$lg(row, 2), !
	     s Vbase = Vbase + $lg(row, 3)
	     s SumBase = SumBase + $lg(row, 2)
	     
	     /// для каждой услуги НЕбазового считаем 
	     s lk = ##class(Charges.EChargesA).getChargesByService(facenum, value, $zdh(td1, 4), servType)
	     w:debug=1 "Основной небазовый на ",td1,": "_servType_", Объем: "_$lg($lg(lk, 1), 3), " Денег: "_$lg($lg(lk, 1), 2), !
	     
	    /// вычисляем для текущего по алгоритму
	    if ($ll(l) = 1){
		     w:debug=1 "Один тип начисления: "_value, !
		    /// если один тип начисления 
		     if ($lg($lg(lk, 1), 2) = ""){
			      if (servType = 2){ s (u, basenorm) = 1 }else{ s u = 2, baseipu = 1}
			      /// определяем по другому типу
			      s lk = ##class(Charges.EChargesA).getChargesByService(facenum, u, $zdh(td1, 4), servType)
			      w:debug=1 "Определили - есть ли начисления по другому типу: "_$lg($lg(lk, 1), 2), !
			     }
		    }else{
			 w:debug=1 "Услуга: "_value_" - "_servType_". Начислено за текущий период денег: "_$lg($lg(lk, 1), 2)_", объем: "_$lg($lg(lk, 1), 3), !
			}
	   
	    s Vcurrent = Vcurrent + $lg($lg(lk, 1), 3)
	    }
	    
	     s tax = ..GetCurTax(value, td1)
		 s taxprodc = $lg(tax, 2)
		 s taxunitc = $lg(tax, 3)
	     s norm = 0 
	 	    
	    /// горячая вода
		 if (value = 91){ 
		  s vk = ##class(Charges.EChargesA).getChargesByService(facenum, value, $zdh(td1, 4), )
	
		  s V = $lg($lg(vk, 1), 3)
		  w:debug=1 "Факт объем ГВС(КТ): "_V, !
		  
		  s sumt = +$lg($lg(vk, 1), 2)

		  s tcurr = ##class(Charges.EChargesA).getChargesByService(facenum, 133, $zdh(td1, 4))
		
	 	  if (+$lg($lg(tcurr, 1), 3) '= 0){
	       s taxprodc = $lg(..GetCurTax(133, td1), 2) 
	       /// плюсуем объем
	       s V = V + $lg($lg(tcurr, 1), 3)

	 	  }else{
		   /// вариант, когда договор содержит начисления, но не содержит тарифа и соответственно сумма = 0
		   if (sumt = 0){
			   s taxprodc = 0
			   }
		   else{
		    s curtax = ..GetCurTax(91, td1)
		   
		    s servType = 0
		    /// берем serviceType 
		    s proDate = $zdh(td1, 4)
		    &sql(select top 1 serviceType into :servType from Charges.EChargesA 
		         where contract->facenum = :facenum and item = 91 and :proDate between ToDataB and ToDataE )
		    
		    s taxprodc = $lg(curtax, 2)
		   }
		  
		  }
		  
		 }elseif (value = 95){
		  if (changeflag '= 2){
		   s vk = ##class(Charges.EChargesA).getChargesByService(facenum, value, $zdh(td1, 4), )
	  	   //zw vk
	  	   s servType = $lg($lg(vk, 1), 1) /// тип начисления
	  	   s (norm ,gvs) = $lg($lg(vk, 1), 3)
		  }else{
	       d ##class(Contracts.EPhDogovor).getNormDG(dgID,$zdh(td1, 4),1,.norm,.normODN,,0) // на тепло
	       
		  }
	      w:debug=1 "Количество ТЭ на нагрев: "_norm, !
	       if ($ll(vk) = 0){
		   s V = 0
		  }else{
		   s V = $lg($lg(vk, 1), 3)
		  }
		  
	      w:debug=1 "Расчетный объем ГВС(КТЭ): "_V, !
		 }elseif(value = 10){
		  s vk = ##class(Charges.EChargesA).getChargesByService(facenum, value, $zdh(td1, 4))	 	 
		  s servType = $lg(vk, 1) /// тип начисления
		  if ($ll(vk) = 0){
		   s V = 0
		  }else{
		   s V = $lg($lg(vk, 1), 3)
		  }
		  w:debug=1 "Текущий объем ГВС: "_V, !
		 } 
	    
	    /// холодная вода
	    if ((value = 131) || (value = 133)){ 
	     s vk = ##class(Charges.EChargesA).getChargesByService(facenum, value, $zdh(td1, 4))	 
	      s servType = $lg($lg(vk, 1), 1) /// тип начисления
	      if ($ll(vk) = 0){
		   s V = 0
		  }else{
		   s V = $lg($lg(vk, 1), 3)
		  }
	  	 w:debug=1 "Расчетный объем ХВС: "_V, !
	    }
	    
	    /// газ
		if (Prod = 15){
	     /// надо проверить, внесены ли показания - расход - факт
	     
	     &sql(select VPotr, Summ, Tax into :vptrgas, :vsummgas, :vgastax from Charges.DropFinance 
	      where facenum = :facenum and Prod = :Prod and BPeriod = :td1 and serviceType = 1)
	     /// не внесены
	     if (+vptrgas = 0){
	      s normgas = ..getGasNormbyHouse(houseid, td1)
	      s V = normgas * humans
	      s norm = normgas
	      s frontV = normgas * fronthumans
	      w:debug=1 "Объем начислений газ: "_V, ! 
	      s servType = 2
	     }else{
		  s V = vptrgas
		   s servType = 1
		 }
	    }
	   
	   if (Prod = 1){
		 /// берем количество человек для текущего периода, из этого определяем необходимую соц. норму
		  &sql(select VPotr, Summ, Tax into :vptree, :vsummee, :veetax from Charges.DropFinance 
	      where facenum = :facenum and Prod = :Prod and BPeriod = :td1 and serviceType = 1)
		 if (+vptree = 0){
		 if (humans * normsne < normee){
		  s V = normee
		  s frontV = normee
		 }else{
		 // соцнорма для человека по ээ
	      s V = humans * normsne
	      s norm = normsne
	      s frontV = fronthumans * normsne
		 }
		 w:debug=1 "Расчетный объем по э/э: "_V, !
		 s servType = 2 /// тип начисления
		 }else{
		  s V = vptree
		  w:debug=1 "Фактический объем по э/э: "_V, !
		  s servType = 1 /// тип начисления
		  }
	     
	    }
	    
	   /// отопление
	    if (value = 11){ 
		  s curr = ##class(Charges.EChargesA).getChargesByService(facenum, value, $zdh(td1, 4))	 	 
		  
		  //zw curr
		  if ($ll(curr) = 0){
		   s norm = ##class(Contracts.EPhDogovor).CalNormT(dgID)
		   s V = 0 
		   w:debug=1 "Норматив отопление: "_norm, !
	       w:debug=1 "Расчетный объем отопления: "_V, ! 
	       s servType = 2 /// тип начисления
		  }else{
		   s norm = $lg($lg(curr, 1), 3)
		   s V = $lg($lg(curr, 1), 3)
		   w:debug=1 "Факт отопление по норме: "_norm, !
	       w:debug=1 "Факт объем отопления: "_V, ! 
	       s servType = 1 /// тип начисления
		  }
		  s proDate = $zdh(td1, 4)
		  
		  &sql(select top 1 serviceType into :servType from Charges.EChargesA 
		         where contract->facenum = :facenum and item = 11 and :proDate between ToDataB and ToDataE )
		  
		  
	     s taxprodc =  ##class(Tarifs.EEBTarifs).SeleTax(dgID, value, $zdh(td1, 4), .taxunitb, .taxprodb)
	   } 
	   /// водоотведение
	   if (Prod = 14){
	  /// если ВО	 
        s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, 141, $zdh(td1, 4)), 1)
        s current = $lg(currPO, 3)
        s servType = $lg(currPO, 1)
       // w servType, !
        s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, 143, $zdh(td1, 4)), 1)
        s current = current + $lg(currPO, 3)
        
        s currPO = $lg(##class(Charges.EChargesA).getChargesByService(facenum, 144, $zdh(td1, 4)), 1)
        s current = current + $lg(currPO, 3)
        
        /*if (servType '= $lg(currPO, 1)){
	      s servType = 1
	    }*/
        
        w:debug=1 "Факт водоотведения: "_current, !
	    s V = current
	   }
	  /// тариф 
	    do ##class(Tarifs.EEBTarifs).SeleTax(dgID, value, $zdh(tdb1, 4), .taxunitb, .taxprodb)
	    s basetaxa = taxunitb
	    
	    if (Prod = 1){
	 /// определяем, есть ли на доме газ
		 s gasBlago = ##class(Address.EHouseDesc).getGasBlagoByHouse(houseid)
		 if (gasBlago = ""){
		  /// значит для эл плит
		  s el = 1	 
		 }else{
		  s el = 0	 
		 }
		 
		 s tax = ..GetCurTax(value, td1, el)
		  w:debug=1 "Тариф(ээ): "_$lg(tax, 2), !
		 /// тариф на превышение соц. нормы
		 s taxLRate = $lg(tax, 4)
		 
		 w:debug=1 "Тариф(ээ превышение сн): "_$lg(tax, 4), !
		 
		 /// если факта нет
		 if (+vptree = 0){
		  /// почему здесь берет текущий???? поменял на тариф из истории
		  s (basetaxa, currtaxa, taxprodc) = $lg(tax, 4)
		 }else{
		  /// если факт есть
		  /// определяем, было ли превышение соц. нормы
		
		  if (vptree < (humans * normsne) ){
		   s (basetaxa, currtaxa, taxprodc) = veetax
		  }else{
		   s (basetaxa, currtaxa, taxprodc) = taxLRate
	      }
		 }
		 
 		  s (taxunitb, taxunitc) = $lg(tax, 3)
		
		}
		
		if (Prod = 15){
		 /// на доме определяем тариф: 			
		 s taxprodc = ..getGasTariffbyHouse(houseid, $zdh(td1, 4))
		 s ctax = ..GetCurTax(value, td1)	
		 s (taxunitb, taxunitc) = $lg(ctax, 3)
		 /// добавить здесь для факта
		}
		
		if (value = 95){
		  s taxprodc = ##class(Tarifs.EEBTarifs).SeleTax(dgID, value, $zdh(td1, 4), .taxunitb, .taxprodb)
		}
		
		if (value = 131){
			
		  s eais = $zdh(td1, 4), tarContract = 0
		  
		  &sql(select top 1 Contract into :tarContract from Charges.EChargesA 
		       where Item = 131 and :eais between ToDataB and ToDataE and Contract->facenum = :facenum )
		  if (+tarContract '= 0){
		   if ($data(^Contract.EPhDogovorD(tarContract, "Taxa", 131)) '= 0){
		    s tarid = ^Contract.EPhDogovorD(tarContract, "Taxa", 131)
		   		 
		    s d1=$O(^Tarifs.EEBTarifsD(tarid,"History",((eais\1)+.01)),-1) 
		    s taxprodc = $lg(^Tarifs.EEBTarifsD(tarid,"History",d1),3)
		   }
		  
		  }else{
		   s taxprodc = 0	  
		  }
		}
				
		if (value = 91){
		 /// здесь ЯВНО берем тариф для хвс на гвс
		 /// определим схему
		 s eais = $zdh(td1, 4), tarContract = 0
	       
	       &sql(select top 1 Contract into :tarContract from Charges.EChargesA 
		       where Item = 133 and :eais between ToDataB and ToDataE and Contract->facenum = :facenum )
		  
		  if (+tarContract '= 0){
		   if ($data(^Contract.EPhDogovorD(tarContract, "Taxa", 133)) '= 0){
		    s tarid = ^Contract.EPhDogovorD(tarContract, "Taxa", 133)
		   		 
		    s d1=$O(^Tarifs.EEBTarifsD(tarid,"History",((eais\1)+.01)),-1) 
		    s taxprodc = $lg(^Tarifs.EEBTarifsD(tarid,"History",d1),3)
		   }
		  
		  }else{
		   s taxprodc = 0	  
		  }	
		  w:debug=1 "Тариф для 91: "_taxprodc, !
		}

		if (value = 141){
		 s eais = $zdh(td1, 4), tarContract = 0
		 s taxa = 0
		 &sql(select top 1 Contract, 
		 (select Taxa from Charges.EGChargesA e where LAGrt = cea.id) iprev 
		 into :tarContract, :taxa 
		 from Charges.EChargesA cea
		       where Item = :value 
		       and   :eais between ToDataB and ToDataE 
		       and   Contract->facenum = :facenum 
		       and   Type <> 30)
		 s taxprodc = taxa	
		}
		
		
	    s SumCurrent = SumCurrent + V * taxprodc

	    if (V >= Vbase){s Vc = Vbase}else{s Vc = V}

	    if ((Prod '= 15) || (Prod '= 1)){
	     s st = ""
		 &sql(declare curt cursor for 
		     select distinct serviceType into :st
		     from Charges.EChargesA where Contract->facenum = :facenum and Type = 1 and Item = :Item and MonthPay = to_date(':td1', 'dd/mm/yyyy'))
		 &sql(open curt)
	 	s lt = ""
		for {
 		 &sql(fetch curt)
 		 if (SQLCODE) q 
 		  if (st = "") continue
 		  s lt = lt_" "_st
		 }
		 s lt = $ZStrip(lt,"<>W")
		 s lt = $replace(lt, " ", ",")
	     &sql(close curt)
	    
	    }
	    
	    s baselist = baselist_"^"_uname_"^"_taxunitc_"^"_Vc_"^"_Vbase_"^"_SumBase_"^"_basetaxa_"^"_norm_"^"_V_"^"_SumCurrent_"^"_taxprodc_"^"_value_"^"_dgID_"^"_Prod_"^"_humans_"^"_kvm_"^"_servType_"^"_frontV_"&"
    // услуга^единица_текущая^факт_объем_текущего^базОбъем^СуммаБаз^базТариф^норматив^ОбъемТек^СуммаТек^ТарифТек^КодУслуги^ДогID^КодПродукции^ЧелПроп^Площадь
    w:debug=1 baselist
    q baselist
}

/// метод определяем газ на доме 
ClassMethod getGasTariffbyHouse(
	houseid As %Integer,
	td1 As %Date)
{
	s tax = 0
	&sql(select top 1 Value into :tax 
	     from Tarifs.gasTariffs 
	     where gasType = (select gasType from Address.EHouseDesc where House = :houseid) and dateStart <= :td1
	     order by dateStart desc)
	q tax
}

/// метод определяем норматив по газу на доме 
ClassMethod getGasNormbyHouse(
	houseid As %Integer,
	td1 As %Date)
{
	s norm = 0
	&sql(select top 1 CurrentGas into :norm 
	     from Normativs.NormativsGas
	     where TypeBlago = (select gasBlago from Address.EHouseDesc where House = :houseid) and dateStart <= :td1
	     order by dateStart desc)
	q norm
}

/// Компании укашки
ClassMethod loadUK(city As %String = "")
{
  s ukList = ##class(%ListOfObjects).%New()
  s SQLQuery = ##class(%SQL.Statement).%New()
  
   s SQLText = "select ECode as ID, Name from Provider.ECompany where Name is not NULL "
  if (city '= ""){
   s SQLText = SQLText_" and City = "_city
  }
  s SQLText = SQLText
              _" group by ECode "
  			  _" order by Name "
  //w SQLText
  d SQLQuery.%Prepare(SQLText)
  s DataRow = SQLQuery.%Execute()    
  while DataRow.%Next(){
   s list = ##class(%ZEN.proxyObject).%New()
   s list.id = DataRow.ID
   s list.name = DataRow.Name
   do ukList.Insert(list)
   kill list
  }	
	q ukList
}

/// для ajax загрузки улиц
ClassMethod loadStreets(
	city As %String = "",
	uk As %String = "") As %ListOfObjects
{
	
  s streetList = ##class(%ListOfObjects).%New()
  s SQLQuery = ##class(%SQL.Statement).%New()
  
   s SQLText = "select ID, Name from Address.EStreet "
  if ((city '= "") || (uk '= "")){
   s SQLText = SQLText_" where "
  }
  if (city '= ""){
   s SQLText = SQLText_" City = "_city
  }
  
  if (uk '= ""){
   //s SQLText = SQLText_" City = "_city	  
  }

  s SQLText = SQLText_" order by Name "
  
  d SQLQuery.%Prepare(SQLText)
  s DataRow = SQLQuery.%Execute()    
  s count = 0 
  while DataRow.%Next(){
   s list = ##class(%ZEN.proxyObject).%New()
   s list.id = DataRow.ID
   s list.name = DataRow.Name
   do streetList.Insert(list)
   kill list
  }	

	q streetList
}

/// для ajax загрузки улиц
ClassMethod loadHouse(street As %String = "") As %ListOfObjects
{
	
  s houseList = ##class(%ListOfObjects).%New()
  s SQLQuery = ##class(%SQL.Statement).%New()
  
   s SQLText = "select ID, NHouse from Address.EStreet "
  if (street '= ""){
   s SQLText = SQLText_" where street = "_street
  }
  
  s SQLText = SQLText_" order by Name "
  
  d SQLQuery.%Prepare(SQLText)
  s DataRow = SQLQuery.%Execute()    
  s count = 0 
  while DataRow.%Next(){
   s list = ##class(%ZEN.proxyObject).%New()
   s list.id = DataRow.ID
   s list.name = DataRow.NHouse
   do houseList.Insert(list)
   kill list
  }	
   q houseList
}

/// сверка текущих начислений ВД и сохраненных
/// период, код дома
/// это в простые отчеты
ClassMethod checkingPlanWithRealVD(
	startperiod As %Date,
	endperiod As %Date,
	house As %Integer = 0) As %ListOfObjects
{
	if (startperiod = "") q -1
	s house = +house
	s n = 0
	s userid = ##class(Auth.SysUser).CheckUser()
  	kill ^mtempSymplyRep(userid)

	&sql(declare vdcr cursor for 
	     select distinct facenum from Contracts.EPhDogovor 
	     where 1 = 1 and (:house = 0 or Address->House = :house)
	    )
	&sql(open vdcr)
	for{
	 &sql(fetch vdcr into :facenum)
	 if (SQLCODE) q
	 /// вычисляем на период по fn сохраненную сумму
	 s nsum = 0
	 // берем даты
	 s startyear = $System.SQL.DATEPART("YYYY", startperiod) // год
	 s endyear = $System.SQL.DATEPART("YYYY", endperiod) // год
	 s startmonth = $System.SQL.DATEPART("MM", startperiod) // месяц
	 s endmonth = $System.SQL.DATEPART("MM", endperiod) // месяц
	 
	 for year = startyear:1:endyear{
	  if (startyear '= endyear){
	  if (endmonth < startmonth){
	   s endcalcmonth = 12 
	   s startcalcmonth = startmonth
	  }else{
	   s endcalcmonth = endmonth
	   s startcalcmonth = 1
	  }
	  
	  }else{
	    s startcalcmonth = startmonth	  
	    s endcalcmonth = endmonth	  
		  
	 }
	  
	  
	  for month = startcalcmonth:1:endcalcmonth{
		  
		if (+month<10){
		 s changedmonth = "0"_month	
		} else {
		 s changedmonth = month	
		}
		s startcalcdate = $zdh("01/"_changedmonth_"/"_year, 4)  
		s endcalcdate = $SYSTEM.SQL.LASTDAY(year_"-"_changedmonth_"-01")  
	    
	    &sql(select sum(Summ) into :nsum 
	      from Charges.EChargesA 
	      where Contract->facenum = :facenum and ToDataE between :startcalcdate and :endcalcdate and Type = 40)
	  s savedSum = -(+$fnumber(nsum, "", 2))
	 /// берем рассчитанную сумму
	 s currentSum = +$fnumber(..getCalculateVD(facenum, startcalcdate), "", 2)
	 s fact = 0
	 &sql(select count(*) into :fact from Charges.DropFinance 
	      where serviceType = 1 and Item = 1002 and facenum = :facenum and periodType is NULL and BPeriod = :startcalcdate
	     )
	 //w facenum, " ", currentSum, " ", savedSum, " " ,"01/"_changedmonth_"/"_year, !
	 if (+currentSum >= 0){ 
	 if (+((+currentSum) - (+savedSum)) '= 0){ 
	  if (+fact = 0){
	   s fact = "Нет"	  
	  }else{
	   s fact = "Да"
	  }
	  set ^mtempSymplyRep(userid,"S",$increment(n))=$lb(facenum, startcalcdate, currentSum, savedSum, fact)
	 }
	 } 
	  
	 }
		 
	  s startmonth = 1
	 }
	 
	}
  	&sql(close vdcr)
  	q 0
}

/// для ajax загрузки укашек
ClassMethod loadCity() As %ListOfObjects
{
	s cityList = ##class(%ListOfObjects).%New()
	&sql(declare stl cursor for select ID, Name from Address.ECity order by Name)
	&sql(open stl)
	for{
	 &sql(fetch stl into :id, :name)
	 if SQLCODE q 
	 s list = ##class(%ZEN.proxyObject).%New()
	 s list.id = id
	 s list.name = name
	 do cityList.Insert(list)
	}
	&sql(close stl)
	q cityList
}

}
