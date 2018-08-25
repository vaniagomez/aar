%macro reserve(id_annuity=,val_i=);

	proc sql noprint;
		/* Edad alcanzada a la fecha actual */
		select num_issueAge + intck('year',fec_issueDate,fec_currentDate) into: x
		from ext.asegurados
		where id_annuity = &id_annuity.
		;
		/* Plazo al vencimiento en la fecha actual */
		select num_originalTotalYearsPayments - intck('year',fec_issueDate,fec_currentDate) into: n
		from ext.asegurados
		where id_annuity = &id_annuity.
		;	
		select mnt_annualPayment format 16.6 into: pymt
		from ext.asegurados
		where id_annuity = &id_annuity.
		;
		select num_originalCertainYears - intck('year',fec_issueDate,fec_currentDate) into: n_cert
		from ext.asegurados
		where id_annuity = &id_annuity.
		;	
		select num_extraPymt into: n_extraPymt
		from ext.asegurados
		where id_annuity = &id_annuity.
		;

	quit;
	
	%put Plazo &n. || Edad alcanzada &x. || Pago &pymt. || Plazo original de los pagos ciertos &n_cert.;
	
	data work.reserves1;		
		do num_year=0 to &n.;
			output;
		end;
	run;
	
	/* Calculamos la edad alcanzada en los años futuros */
	data work.reserves2;
		format id 10.;
		set work.reserves1;
		id = &id_annuity.;
		if num_year > 0 then
			do;
			num_attainedAge = &x.+num_year-1;
			end;
	run;
	
	/* Agregamos la tasa de mortalidad */
	
	proc sql;
		create table work.reserves3 as
		select a.*, b.val_1000qx, 1-val_1000qx/1000 as val_px, 1/(1+&val_i.) as val_intFact
		from work.reserves2 a left join ext.tablamortalidad b on a.num_attainedAge = b.val_age
		;
	run;
	
	/* Agregamos la probabilidad de supervivencia acumulada */
	
	data work.reserves4(drop=val_aux2 val_aux3);
		set work.reserves3;
		val_aux2 + log(val_px);
		val_cumPx = exp(val_aux2);	
		val_aux3 + log(val_intFact);
		val_cumIntFact = exp(val_aux3);
	run;
	
	/* Agregamos los pagos ciertos contingentes */
	
	data work.reserves5;
		set work.reserves4;
		if num_year > 0 and num_year <= &n_cert then
			do;
				mnt_projPymtCert = &pymt.;
			end;
		else
			mnt_projPymtCert = 0;		
		
	run;
	
	/* Agregamos los pagos ciertos contingentes */
	data work.reserves6;
		set work.reserves5;
		if num_year > &n_cert and num_year < &n. then
			do;
				mnt_projPymtCont = &pymt. * val_cumPx;
			end;
		if num_year = &n. then
			do;
				mnt_projPymtCont = (&pymt.+&n_extraPymt.*&pymt.)*val_cumPx;
			end;
	run;
	
	/* Calculamos las reservas */
	data work.reserves7;
		set work.reserves6;
		mnt_projPymtTot=sum(mnt_projPymtCont,mnt_projPymtCert);
	run;
	
	data _null_;
		set work.reserves6;
		nom = "n_"||compress(put(_n_,2.));
		call symputx(nom,num_year,'L');
	run;
	
	proc sql noprint;
		select max(num_year) into: max_num_year
		from work.reserves7 
		;
	quit;
	
	%do i=0 %to &max_num_year.;
	
		proc sql noprint;
			select mnt_projPymtCert format 16.2 into: arrayPymt_&i. separated by ','
			from work.reserves7 
			where num_year > &i. 
			;
			select mnt_projPymtCont format 16.2 into: arrayPymtCont_&i. separated by ','
			from work.reserves7 
			where num_year > &i. 
			;			
		quit;	
		
		%put Pagos Ciertos: &&&&arrayPymt_&&i. || Pagos contigentes &&&&arrayPymtCont_&&i. ;
		
		%if %symexist(arrayPymt_&i.) %then		
			
			%do;
			
			%put Pagos Ciertos: &&&&arrayPymt_&&i. || Pagos contigentes &&&&arrayPymtCont_&&i. ;
			
				data work.resAux_&i;
					format mnt_reserveCertain mnt_reserveLifeCont format comma16.2;
					num_year = &i.;
					mnt_reserveCertain = netpv(&val_i.,1,0,&&&&arrayPymt_&&i.);
					mnt_reserveLifeCont = netpv(&val_i.,1,0,&&&&arrayPymtCont_&&i.);
				run;
				
			%put NPV = &&&&arrayPymtNPV_&&i.;
				
			%end;
			
			
		%else
			%do;
				data work.resAux_&i;
					format mnt_reserveCertain mnt_reserveLifeCont format comma16.2;
					num_year = &i.;
					mnt_reserveCertain = 0;
					mnt_reserveLifeCont = 0;
				run;			
			%end;

			
	
	%end;
	
	data work.resAux(keep=num_year mnt_reserveCertain mnt_reserveLifeCont);
		set work.resAux_:;
	run;
	
	proc sql;
		create table work.reserves8 as
			select a.*, b.mnt_reserveCertain, b.mnt_reserveLifeCont, sum(b.mnt_reserveCertain,b.mnt_reserveLifeCont) format comma16.2 as mnt_reserveTotal
			from work.reserves7 a inner join work.resAux b on a.num_year = b.num_year
			;
	quit;
	
	/* Limpieza de la librería work */
	
	data work.res_id_&id_annuity.;
		set work.reserves8;
	run;
	
	proc datasets lib=work nolist;
		delete reserves: resaux:;
	run;

%mend;

