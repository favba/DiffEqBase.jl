struct StandardODEProblem end

# Mu' = f
struct ODEProblem{uType,tType,isinplace,F,C,MM,PT} <:
               AbstractODEProblem{uType,tType,isinplace}
  f::F
  u0::uType
  tspan::Tuple{tType,tType}
  callback::C
  mass_matrix::MM
  problem_type::PT
  function ODEProblem{iip}(f,u0,tspan,problem_type=StandardODEProblem();
                      callback=nothing,mass_matrix=I) where {iip}
    if mass_matrix == I && typeof(f) <: Tuple
      _mm = ((I for i in 1:length(f))...)
    else
      _mm = mass_matrix
    end
    new{typeof(u0),promote_type(map(typeof,tspan)...),
       iip,typeof(f),typeof(callback),typeof(_mm),typeof(problem_type)}(
       f,u0,tspan,callback,_mm,problem_type)
  end
end

function ODEProblem(f,u0,tspan;kwargs...)
  iip = typeof(f)<: Tuple ? isinplace(f[2],3) : isinplace(f,3)
  ODEProblem{iip}(f,u0,tspan;kwargs...)
end

abstract type AbstractDynamicalODEProblem end

struct DynamicalODEProblem{iip} <: AbstractDynamicalODEProblem end
# u' = f1(v)
# v' = f2(t,u)

struct DynamicalODEFunction{iip,F1,F2} <: Function
    f1::F1
    f2::F2
    DynamicalODEFunction{iip}(f1,f2) where iip =
                        new{iip,typeof(f1),typeof(f2)}(f1,f2)
end
function (f::DynamicalODEFunction)(t,u)
    ArrayPartition(f.f1(t,u.x[1],u.x[2]),f.f2(t,u.x[1],u.x[2]))
end
function (f::DynamicalODEFunction)(t,u,du)
    f.f1(t,u.x[1],u.x[2],du.x[1])
    f.f2(t,u.x[1],u.x[2],du.x[2])
end

function DynamicalODEProblem(f1,f2,u0,du0,tspan;kwargs...)
  iip = isinplace(f1,4)
  DynamicalODEProblem{iip}(f1,f2,u0,du0,tspan;kwargs...)
end
function DynamicalODEProblem{iip}(f1,f2,u0,du0,tspan;kwargs...) where iip
    ODEProblem{iip}(DynamicalODEFunction{iip}(f1,f2),(u0,du0),tspan;kwargs...)
end

# u'' = f(t,u,du,ddu)
struct SecondOrderODEProblem{iip} <: AbstractDynamicalODEProblem end
function SecondOrderODEProblem(f,u0,du0,tspan;kwargs...)
  iip = isinplace(f,4)
  SecondOrderODEProblem{iip}(f,u0,du0,tspan;kwargs...)
end
function SecondOrderODEProblem{iip}(f,u0,du0,tspan;kwargs...) where iip
  if iip
    f1 = function (t,u,v,du)
      du .= v
    end
  else
    f1 = function (t,u,v)
      v
    end
  end
  _f = (f1,f)
  _u0 = (u0,du0)
  ODEProblem{iip}(DynamicalODEFunction{iip}(f1,f),_u0,tspan,
                  SecondOrderODEProblem{iip}();kwargs...)
end

struct SplitFunction{iip,F1,F2,C} <: Function
    f1::F1
    f2::F2
    cache::C
    SplitFunction{iip}(f1,f2,cache) where iip =
                        new{iip,typeof(f1),typeof(f2),typeof(cache)}(f1,f2,cache)
end
function (f::SplitFunction)(t,u)
    f.f1(t,u) + f.f2(t,u)
end
function (f::SplitFunction)(t,u,du)
    f.f1(t,u,f.cache)
    f.f2(t,u,du)
    du .+= f.cache
end

abstract type AbstractSplitODEProblem end
struct SplitODEProblem{iip} <: AbstractSplitODEProblem end
# u' = Au + f
function SplitODEProblem(f1,f2,u0,tspan;kwargs...)
  iip = isinplace(f2,3)
  SplitODEProblem{iip}(f1,f2,u0,tspan;kwargs...)
end
function SplitODEProblem{iip}(f1,f2,u0,tspan;
                                     func_cache=nothing,kwargs...) where iip
  iip ? _func_cache = similar(u0) : _func_cache = nothing
  ODEProblem{iip}(SplitFunction{iip}(f1,f2,_func_cache),u0,tspan,SplitODEProblem{iip}();kwargs...)
end

"""
    set_u0(prob::ODEProblem, u0) -> newprob
Create a new problem from `prob` that has instead initial state `u0`.
"""
function set_u0(prob::ODEProblem, u0)
    ODEProblem{isinplace(prob)}(
    prob.f,
    u0,
    prob.tspan,
    prob.callback,
    prob.mass_matrix,
    prob.problem_type)
end

export set_u0
