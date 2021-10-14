! ************************************************************************
! Filename : neogrowth_deterministic.f90
!
! Author : Philip Coyle
!
! Date Created : September 7th, 2021
!
! Description : This program will use dynamic programming techniques to solve
! a simple neoclassical growth model with a two state markov productivity shock.
!
! Notes:
! I run my fortan code from the terminal. I included the commands I need to run
! in the terminal.
! First, I chage into the appropriate directory.
! Second I compile the code. gfortran is my compiler. I will go over what all the dashes mean when we meet.
! Finally, I run the compiled (machine readbale) code. This is running the program.
! You should update the path -- the part that is "cd ..." -- to where you store the file.
!
! Routine:
! cd econ899
! gfortran -O2 -o neogrowth_stochastic neogrowth_stochastic_hj.f90
! ./neogrowth_stochastic
! ************************************************************************

! ************************************************************************
! ------------------------------------------------------------------------
! ------------------------------------------------------------------------
! module : params_grid
!
! Description : This module will form the foudation for our program. In it
! we will allocate space for all paramaters used in this program and set up the
! grids to create a discritized state space
! ------------------------------------------------------------------------
! ------------------------------------------------------------------------

module params_grid

implicit none

! -----------------------------------------------------------------------
! *******************DECLARATION OF PARAMETERS AND VARIABLES*************
! -----------------------------------------------------------------------
! Model Parameters
double precision, parameter :: 				cBET 				= 0.99d0
double precision, parameter :: 				cTHETA 			= 0.36d0
double precision, parameter :: 				cDEL 				= 0.025d0

! Model Probabilities
double precision, parameter :: 				Pgg 				= 0.977d0
double precision, parameter :: 				Pbg 				= 1d0 - Pgg
double precision, parameter :: 				Pbb 				= 0.926d0
double precision, parameter :: 				Pgb 				= 1 - Pbb
double precision	 				  :: 				Pr(2)


! Tolerance level for convergence and max itations
double precision, parameter :: 				tol			 		= 1d-4!
integer, parameter 					:: 				max_it 			= 10000
integer 										::				it		 			= 1 !itation counter
integer 										:: 				converged		= 0


! -----------------------------------------------------------------------
! ****************************GRID SET**********************************
! -----------------------------------------------------------------------
! Set up for discritizing the state space (Capital Grid)
integer						 				  :: 				i_k, i_kpr
integer, parameter 				  :: 				n_k 				= 1000
double precision 						:: 				grid_k(n_k)
double precision, parameter :: 				min_k 			= 0.01d0 !1d0
double precision, parameter :: 				max_k 			= 45d0 !75d0
double precision, parameter :: 				step_k 			= (max_k - min_k)/(dble(n_k) - 1d0)
double precision					  :: 				k_today
double precision					  :: 				k_tomorrow

! Set up for discritizing the state space (Productivity Grid)
integer						 				  :: 				i_Z
double precision, parameter :: 				Zg 					= 1.25d0
double precision, parameter :: 				Zb 					= 0.2d0
integer, parameter 				  :: 				n_Z 				= 2
double precision 						:: 				grid_Z(n_Z)
double precision					  :: 				Z_today

integer 										:: 				i_state
integer, parameter  				:: 				n_state 		= n_k*n_Z ! Writing grid in one whole loop

! Global variables for Dynamic Progamming
double precision 						:: 				c_today
double precision 						:: 				c_today_temp
double precision 						:: 				y_today
double precision 						:: 				k_tomorrow_max
double precision 						:: 				v_today
double precision 						:: 				v_today_temp
double precision 						:: 				v_tomorrow


! Allocating space for Policy Functions
double precision 						:: 				pf_c(n_k, n_Z)
double precision 						:: 				pf_k(n_k, n_Z)
double precision 						:: 				pf_v(n_k, n_Z)

integer 										::			  i_stat
integer 										::			  iMaxThreads

end module params_grid


! ************************************************************************
! ------------------------------------------------------------------------
! ------------------------------------------------------------------------
! program : neogrowth
!
! Description : This program will use dynamic programming techniques to solve
! a simple deterministic neoclassical growth model.
! ------------------------------------------------------------------------
! ------------------------------------------------------------------------

program neogrowth

use params_grid
use omp_lib



implicit none

! Begin Computational Timer
integer 										::				beginning, end, rate

call system_clock(beginning, rate)

! Initialize Grids and Policy Functions
call housekeeping()

! Do Value Function Iteration
call bellman()

call system_clock(end)
write(*,*) ""
write(*,*) "******************************************************"
write(*,*) "Total elapsed time = ", real(end - beginning) / real(rate)," seconds"
write(*,*) "******************************************************"

! Write results
call coda()

write(*,*) ""
write(*,*) "**************************************"
write(*,*) "************END OF PROGRAM************"
write(*,*) "**************************************"
write(*,*) ""

end program neogrowth

! ************************************************************************
! ************************************************************************
! ************************************************************************
! **************************** SUBROUTINES *******************************
! ************************************************************************
! ************************************************************************
! ************************************************************************


! ************************************************************************


! ------------------------------------------------------------------------
! ------------------------------------------------------------------------
! subroutine : housekeeping
!
! description : Initializes Grids and Policy Functions
! ------------------------------------------------------------------------
! ------------------------------------------------------------------------

subroutine housekeeping()

use params_grid
use omp_lib

implicit none

! Discretizing the state space (capital)
do i_k = 1,n_k
	grid_k(i_k) = min_k + (dble(i_k) - 1d0)*step_k
end do

do i_z = 1,n_z
	if(i_z==1) then
		grid_z(i_z) = zg
	else
		grid_z(i_z) = zb
	end if
end do

! Setting up Policy Function guesses
do i_z = 1,n_z
	do i_k = 1,n_k
		pf_c(i_k, i_z) 			    = 0d0
		pf_k(i_k, i_z) 		    	= 0d0
		pf_v(i_k, i_z)   	      = 0d0
	end do
end do

return

end subroutine housekeeping




! ************************************************************************


! ------------------------------------------------------------------------
! ------------------------------------------------------------------------
! subroutine : bellman
!
! description : Solves the dynamic programming problem for policy and value
! functions.
! ------------------------------------------------------------------------
! ------------------------------------------------------------------------

subroutine bellman()

use params_grid
use omp_lib

implicit none
! allocating space for policy function updates
double precision 						:: 				pf_c_up(n_k, n_z)
double precision 						:: 				pf_k_up(n_k, n_z)
double precision 						:: 				pf_v_up(n_k, n_z)

double precision 						:: 				diff_c
double precision 						:: 				diff_k
double precision 						:: 				diff_v
double precision 						:: 				max_diff


converged = 0
it = 1

! Begin Dynamic Programming Algo.
! Continue to iterate while VFI has not converged (converged == 0) and iteration counter is less than maximium numnber of iterations (it < max_it)
do while (converged == 0 .and. it < max_it)

	do i_z = 1,n_z
		z_today = grid_z(i_z)
		if(i_z==1) then
			Pr(1) = Pgg
			Pr(2) = Pbg
		else
			Pr(1) = Pgb
			Pr(2) = Pbb
		end if

		do i_k = 1,n_k ! Loop over all possible capital states

			! ***********************************
			! Define the today's state variables
			! ***********************************
			k_today = grid_k(i_k)

			! ******************************************************
			! Solve for the optimal consumption / capital investment
			! ******************************************************
			v_today = -1d10 ! Set a very low bound for value
			y_today = z_today*k_today**(cTHETA) ! income today
			do i_kpr = 1,n_k ! Loop over all possible capital chocies
				k_tomorrow = grid_k(i_kpr)

				! some values are "temp" values because we are searching exaustively for the capital/consumption choice that maximizes value
				c_today_temp = y_today + (1-cDEL)*k_today - k_tomorrow
				v_tomorrow = Pr(1)*pf_v(i_kpr,1)+Pr(2)*pf_v(i_kpr,2) ! when we select i_kpr as a next capital, v_tomorrow value is determined by the weighted average of probability.


				c_today_temp = max(0d0,c_today_temp)
				v_today_temp = log(c_today_temp) + cBET*v_tomorrow

				if (v_today_temp > v_today) then ! if "temp" value is best so far, record value and capital choice: Essentially save the highest value!
					v_today = v_today_temp
					k_tomorrow_max = k_tomorrow
				end if

			end do

			k_tomorrow = k_tomorrow_max
			c_today = y_today + (1-cDEL)*k_today - k_tomorrow

	   	! *******************************
		  ! ****Update Policy Functions****
		  ! *******************************
		  pf_c_up(i_k, i_z) = c_today
		  pf_k_up(i_k, i_z) = k_tomorrow
		  pf_v_up(i_k, i_z) = v_today
		end do
	end do

	! Find the difference between the policy functions and updates
	diff_c  = maxval(abs(pf_c - pf_c_up))
	diff_k  = maxval(abs(pf_k - pf_k_up))
	diff_v  = maxval(abs(pf_v - pf_v_up))

	max_diff = diff_c + diff_k + diff_v

	if (mod(it,50) == 0) then
		write(*,*) ""
		write(*,*) "********************************************"
		write(*,*) "At itation = ", it
		write(*,*) "Max Difference = ", max_diff
		write(*,*) "********************************************"
	 end if

	if (max_diff < tol) then
		converged = 1
		write(*,*) ""
		write(*,*) "********************************************"
		write(*,*) "At itation = ", it
		write(*,*) "Max Difference = ", max_diff
		write(*,*) "********************************************"
	end if

	it = it+1

	pf_c 		= pf_c_up
	pf_k 		= pf_k_up
	pf_v		= pf_v_up
end do

return

end subroutine bellman

! ************************************************************************


! ------------------------------------------------------------------------
! ------------------------------------------------------------------------
! subroutine : coda
!
! description : Writes results to .dat file
! ------------------------------------------------------------------------
! ------------------------------------------------------------------------

subroutine coda()

use params_grid


implicit none

write(*,*) ""
write (*,*) "Writing PFs to DAT file"
open(unit = 2, file = 'pfs_neogrowth.dat', status = 'replace', action = 'write', iostat = i_stat)
200 format(f25.15,2x,f25.15,2x,f25.15,2x,f25.15,2x,f25.15,2x,f25.15,2x,f25.15,2x,f25.15,2x) !f25.15: the format of the number--quite large. 2x: spacing between two numbers

do i_z = 1,n_z
	do i_k = 1,n_k
		write(2,200) grid_z(i_z), grid_k(i_k), pf_c(i_k, i_z), pf_k(i_k, i_z), pf_v(i_k, i_z)  ! coincides with 2 and 200 in the above line.
	end do
end do

return

end subroutine coda
