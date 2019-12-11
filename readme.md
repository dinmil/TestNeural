Here is the problem:

This program contains real sample data that is taken from some betting system.

Because, system accepts 800.000 betslips (tickets) per day, and because
about 10.000 tickets are previewed by risk employees, and because only
one percent of tickets are really rejected, I want to make AI network 
which will automatically approve, reject or negotiate betslips.
Risk employees count is about 10, and everybody have different opinions 
about approving, rejecting and negotiating.
So the output is not clean or predictable.

Every betslip contain 93 parameters which somehow describe betslip:
  - is it dangerous
  - how much duplicate in system 
  - is customer dangerous
  - what is most played sport on ticket 
  - how much the price is different than competition
etc.

Output can be:
  - ticket is accepted
  - ticket is negotiated for smaller amount or smaller price
  - ticket is rejected
 
I tried first with one output which will be
  - 0.1 for approve
  - 0.5 for negotiate
  - 0.9 for reject
, but I was not succesfull.

The I switch to 3 parameters:
  approve   is 0.9 and 0.1 and 0.1
  negotiate is 0.1 and 0.9 and 0.1
  reject    is 0.1 and 0.1 and 0.9

So 0.1 is unset and 0.9 is set.
I had much more success but I noticed that 
last (3rd) computed output is always 0 
(do not know the reason - maybe some library problem).

Then I introduced 4 parameters, and this last one is always 0.5 ,
when network is learning.
When computed, this param is always 0 as expected (because of some bug, or....)

The best result I  achieve by making network like this

  // Create network - so far 93 params
  _NNet.AddLayer(TNNetInput.Create(Length(TInputArray)));

  _NNet.AddLayer( TNNetFullConnectReLU.Create(MyFirstLayerCount) );
  _NNet.AddLayer( TNNetFullConnectReLU.Create(MySecondLayerCount) );
  _NNet.AddLayer( TNNetSoftMax.Create());

  // Last layer have 4 outputs
  _NNet.AddLayer( TNNetFullConnectReLU.Create(Length(TOutputArray)) );

Network, can predict approved ticket successfully but rejected and negotiated are problem.
Maybe, data are the problem. 
Test_data.csv is super set of train_data.csv. 
Train_data contain every 6th approved ticket and every rejected or negotiated ticket 
from test_data. This make 10 percent of rejected tickets in train_data.csv. sample.


Important thing for network is not to approve ticket which is really rejected!!!!
And second important thing is to approve as much as possible (so far about 90 percent).

Can I make better, and why 4th param is always 0?



