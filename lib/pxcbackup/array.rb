class Array
  def uniq_by(&blk)
    transforms = {}
    select do |el|
      t = blk[el]
      should_keep = !transforms[t]
      transforms[t] = true
      should_keep
    end
  end
end
