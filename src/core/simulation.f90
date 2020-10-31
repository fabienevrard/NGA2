!> Various definitions and tools for running an NGA2 simulation
module simulation
   use incomp_class,      only: incomp,dirichlet
   use geometry,          only: cfg
   use ensight_class,     only: ensight
   use timetracker_class, only: timetracker
   implicit none
   private
   
   !> Single incompressible flow solver and corresponding time tracker
   type(incomp),      public :: fs
   type(timetracker), public :: time
   
   !> Ensight postprocessing
   type(ensight) :: ens_out
   
   public :: simulation_init,simulation_run
   
contains
   
   !> Function that localizes the top of the domain
   function yplus_locator(pg,i,j,k) result(isIn)
      use pgrid_class, only: pgrid
      class(pgrid), intent(in) :: pg
      integer, intent(in) :: i,j,k
      logical :: isIn
      isIn=.false.
      if (j.eq.pg%jmax+1) isIn=.true.
   end function yplus_locator
   
   
   !> Initialization of problem solver
   subroutine simulation_init
      use precision, only: WP
      use param,     only: param_read
      use ils_class, only: rbgs,amg
      implicit none
      
      ! Create an incompressible flow solver
      create_solver: block
         ! Create solver
         fs=incomp(cfg,'Bob')
         ! Assign constant fluid properties
         call param_read('Density',fs%rho)
         call param_read('Dynamic viscosity',fs%visc)
         ! Configure pressure solver
         fs%psolv%maxit=100
         fs%psolv%acvg=1.0e-4_WP
         fs%psolv%rcvg=1.0e-4_WP
         ! Initialize solver
         call fs%psolv%init_solver(amg)
         ! Check solver objects
         call fs%print()
      end block create_solver
      
      
      ! Initialize boundary conditions
      initialize_bc: block
         call fs%add_bcond('stokes',dirichlet,yplus_locator)
      end block initialize_bc
      
      
      ! Initialize time tracker
      initialize_timetracker: block
         time=timetracker()
      end block initialize_timetracker
      
      
      ! Initialize our velocity field
      initialize_velocity: block
         fs%U=0.0_WP
         fs%V=0.0_WP
         fs%W=0.0_WP
      end block initialize_velocity
      
      
      ! Add Ensight output
      create_ensight: block
         ! Create Ensight output from cfg
         ens_out=ensight(cfg,'test')
         ! Add variables to output
         call ens_out%add_scalar('Pressure',fs%P)
         call ens_out%add_vector('Velocity',fs%U,fs%V,fs%W)
      end block create_ensight
      
      
      ! Try to use the pressure solver
      test_pressure_solver: block
         ! Create a scaled RHS and output it
         fs%psolv%rhs=0.0_WP
         if (fs%cfg%jproc.eq.         1) fs%psolv%rhs(:,fs%cfg%jmin_,:)=+1.0_WP
         if (fs%cfg%jproc.eq.fs%cfg%npy) fs%psolv%rhs(:,fs%cfg%jmax_,:)=-1.0_WP
         fs%psolv%rhs=-fs%cfg%vol*fs%psolv%rhs
         call ens_out%add_scalar('RHS',fs%psolv%rhs)
         ! Set initial guess to zero
         fs%psolv%sol=0.0_WP
         ! Call the solver
         call fs%psolv%solve()
         ! Copy back to pressure
         fs%P=fs%psolv%sol
         call fs%psolv%print()
         ! Output to ensight
         call ens_out%write_data(0.0_WP)
      end block test_pressure_solver
      
      
   end subroutine simulation_init
   
   
   
   !> Perform an NGA2 simulation
   subroutine simulation_run
      use precision, only: WP
      implicit none
      real(WP), dimension(:,:,:), allocatable :: dudt,dvdt,dwdt
      
      ! Allocate work arrays
      allocate(dudt(fs%cfg%imino_:fs%cfg%imaxo_,fs%cfg%jmino_:fs%cfg%jmaxo_,fs%cfg%kmino_:fs%cfg%kmaxo_))
      allocate(dvdt(fs%cfg%imino_:fs%cfg%imaxo_,fs%cfg%jmino_:fs%cfg%jmaxo_,fs%cfg%kmino_:fs%cfg%kmaxo_))
      allocate(dwdt(fs%cfg%imino_:fs%cfg%imaxo_,fs%cfg%jmino_:fs%cfg%jmaxo_,fs%cfg%kmino_:fs%cfg%kmaxo_))
      
      ! Some time stuff - unclear where to put this
      !ntime=1
      !time=0.0_WP
      !max_time=1.0_WP
      !dt=0.01_WP
      
      do while (time%time.lt.time%max_time)
         ! Evaluate velocity rate of change
         call fs%get_dmomdt(dudt,dvdt,dwdt)
         ! Explicit Euler advancement
         fs%U=fs%U+time%dt*dudt/fs%rho
         fs%V=fs%V+time%dt*dvdt/fs%rho
         fs%W=fs%W+time%dt*dwdt/fs%rho
         ! Increment time
         call time%increment()
      end do
      
      ! Deallocate work arrays
      deallocate(dudt,dvdt,dwdt)
      
   end subroutine simulation_run
   
   
end module simulation
