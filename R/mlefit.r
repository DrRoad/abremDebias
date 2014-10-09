mlefit<-function(x, dist="weibull", debias=NULL, optcontrol=NULL)  {
## tz is required for MLEloglike and MLEsimplex calls now		
		default_tz=0
			
## check basic parameters of x				
	if(class(x)!="data.frame") {stop("mlefit takes a structured dataframe input, use mleframe")}			
	if(ncol(x)!=3)  {stop("mlefit takes a structured dataframe input, use mleframe")}			
	xnames<-names(x)			
	if(xnames[1]!="left" || xnames[2]!="right"||xnames[3]!="qty")  {			
		 stop("mlefit takes a structured dataframe input, use mleframe")  }		
## test for any na's and stop, else testint below will be wrong				
				
				
## need this length information regardless of input object formation				
	testint<-x$right-x$left			
	failNDX<-which(testint==0)			
	suspNDX<-which(testint<0)			
	Nf<-length(failNDX)			
	Ns<-length(suspNDX)			
	discoveryNDX<-which(x$left==0)			
	Nd<-length(discoveryNDX)			
	intervalNDX<-which(testint>0)			
	interval<-x[intervalNDX,]			
	intervalsNDX<-which(interval$left>0)			
	Ni<-length(intervalsNDX)					
				
## further validate the input arguments for non-fsiq object				
	if(length(attributes(x)$fsiq)!=1)  {							
## stop if Nf+Ns+Ndi != nrow(x)				
	if( (Nf+Ns+Nd+Ni) != nrow(x))  {			
		stop("invalid input dataframe")		
	}				
## rebuild input vector from components, just to be sure				
	fsiq<-rbind(x[failNDX,], x[suspNDX,], x[discoveryNDX,], interval[intervalsNDX,])			
## end input validation code				
	}else{			
		fsiq<-x		
	}	

## Not sure what to place as restriction for C++ call	
##	if((Nf+Ni)<3)  {stop("insufficient failure data")}	

			
## now form the arguments for C++ call				
## fsdi is the time vector to pass into C++
## data_est is used to estimate the magnitude of data	
	fsd<-NULL
	data_est<-NULL
	if((Nf+Ns)>0)  {
		fsd<-fsiq$left[1:(Nf + Ns)]
## assure that data_est is a clone		
		data_est<-fsiq$left[1:(Nf + Ns)]
	}
	if(Nd>0) {		
		fsd<-c(fsd,fsiq$right[(Nf + Ns + 1):(Nf +  Ns + Nd)])
		data_est <- c(data_est, 0.5*(fsiq$right[(Nf + Ns + 1):(Nf + Ns + Nd)]))
	}		
	if(Ni>0)  {		
		fsdi<-c(fsd, fsiq$left[(Nf + Ns + Nd + 1):nrow(fsiq)], 	
		fsiq$right[(Nf + Ns + Nd + 1):nrow(fsiq)])
		data_est<-c(data_est, (fsiq$left[(Nf + Ns + Nd + 1):nrow(fsiq)] + 
				 fsiq$right[(Nf + Ns + Nd + 1):nrow(fsiq)])/2)		  
	}else{
		fsdi<-fsd
		data_est<-fsd
	}
	
	q<-fsiq$qty			
## third argument will be c(Nf,Ns,Nd,Ni)				
	N<-c(Nf,Ns,Nd,Ni)
			
## establish distribution number
	if(tolower(dist)=="weibull" || tolower(dist)=="weibull2p" || tolower(dist)=="weibull3p")  {
		dist_num=1
		m <- mean(log(data_est))			
		v <- var(log(data_est))			
		shape <- 1.2/sqrt(v)			
		scale <- exp(m + 0.572/shape)			
		vstart <- c(shape, scale)

	}else{
		if(tolower(dist)=="lognormal"|| tolower(dist)=="lognormal2p"|| tolower(dist)=="lognormal3p")  {
			dist_num=2
			ml <- mean(log(data_est))
			sdl<- sd(log(data_est))
			vstart<-c(ml,sdl)
		}else{
			stop("distribution not resolved")
		}
	}
	
## Optional optimization control list to be handled here				
		## vstart will be as estimated	
		limit<-1e-5	
		maxit<-100	
		listout<-FALSE	
			
	if(length(optcontrol)>0)  {		
		if(length(optcontrol$vstart>0))  {	
			vstart<-optcontrol$vstart
		}	
		if(length(optcontrol$limit)>0)  {	
			limit<-optcontrol$limit
		}	
		if(length(optcontrol$maxit)>0)  {	
			maxit<-optcontrol$maxit
		}	
		if(length(optcontrol$listout)>0)  {	
			listout<-optcontrol$listout
		}	
	}

	pos<-1			
	Q<-sum(q)			
	for(j in seq(1,4))  {			
		if(N[j]>0) {		
			Q<-c(Q, sum(q[pos:(pos+N[j]-1)]))	
			pos<-pos+N[j]	
		}else{		
			Q<-c(Q, 0)	
		}		
	}			
	names(Q)<-c("n","fo", "s", "d", "i")	

	MLEclassList<-list(fsdi=fsdi,q=q,N=N)
## Test for successful log-likelihood calculation with given vstart	
## tz is required for MLEloglike call now				
		LLtest<-.Call("MLEloglike",MLEclassList,vstart,dist_num, default_tz, package="abremDebias")	
		if(!is.finite(LLtest))  {	
			stop("Cannot start optimization with given parameters")
		}	
	
	ControlList<-list(dist_num=dist_num,limit=limit,maxit=maxit)
	
## Handle the original 2 parameter case first	
	if(tolower(dist)=="weibull" || tolower(dist)=="lognormal" ||tolower(dist)=="weibull2p" || tolower(dist)=="lognormal2p"  )  {
		
## listout control is passed as an integer to C++, this enables temporary change of status without losing input argument value

			if(listout==TRUE)  {
				listout_int<-1
			}else{
				listout_int<-0
			}
##  tz  inserted here with a default of zero		
		result_of_simplex_call<-.Call("MLEsimplex",MLEclassList, ControlList, vstart, default_tz, listout_int, package="abremDebias")
## extract fit vector from result of call to enable finishing treatment of the outvec	
		if(listout==FALSE)  {
			resultvec<-result_of_simplex_call
		}else{
			resultvec<-result_of_simplex_call[[1]]
		}
		outvec<-resultvec[1:3]	
		if(resultvec[4]>0)  {	
			warn<-"likelihood optimization did not converge"
			attr(outvec,"warning")<-warn
		}	
		
		if(dist_num == 1)  {			
			names(outvec)<-c("Eta","Beta","LL")		
			if(length(debias)>0)  {	
				if(debias!="rba"&&debias!="mean"&&debias!="hirose-ross")  {	
					stop("debias method not resolved")
				}	
				if(debias=="rba")  {						
					outvec[2]<-outvec[2]*rba(Q[1]-Q[3], dist="weibull",basis="median")
				}	
				if(debias=="mean")  {	
					outvec[2]<-outvec[2]*rba(Q[1]-Q[3], dist="weibull",basis="mean")
				}	
				if(debias=="hirose-ross")  {						
					outvec[2]<-outvec[2]*hrbu(Q[1]-Q[3], Q[3])
				}
			outvec[3]<-.Call("MLEloglike",MLEclassList,c(outvec[2],outvec[1]),dist_num, default_tz, package="abremDebias")	
			attr(outvec,"bias_adj")<-debias
			}		
		}			
					
		if(dist_num == 2)  {			
			names(outvec)<-c("Mulog","Sigmalog","LL")		
			if(length(debias)>0)  {				
				outvec[2]<-outvec[2]*rba(Q[1]-Q[3], dist="lognormal")
				if(debias!="rba")  {	
					warning("rba has been applied to adjust lognormal")
					debias="rba"
				}
			outvec[3]<-.Call("MLEloglike",MLEclassList,c(outvec[1],outvec[2]),dist_num, default_tz, package="abremDebias")	
			attr(outvec,"bias_adj")<-debias	
			}	
		}
		
		
		if(listout==TRUE) {
			optDF<-as.data.frame(result_of_simplex_call[[2]])
			if(dist_num == 1)  {
				names(optDF)<-c("beta_est", "eta_est", "negLL", "error")
			}
			if(dist_num == 2)  {
				names(optDF)<-c("mulog_est", "sigmalog_est", "negLL", "error")
			}		
		}
		
## end of 2p code	
	}

## the following applies to both 2p and 3p results
	attr(outvec,"data_types")<-Q[-2]
	if(listout==FALSE) {	
		return(outvec)
	}else{	
		return(list(fit=outvec, opt=optDF))
	}	

## end function	
}				
