#!/bin/bash

{

VERSION="0.1.0"
YEAR=`date "+%Y"`
DB_DIR=./.highled
CONFIG_FILE="$DB_DIR/config"
DB_DATAFILE="$DB_DIR/$YEAR-balance.ldg"
TRANSACTION_FILE="$DB_DIR/transaction.ldg"
DB_TMPFILE="$DB_DIR/tmp.ldg"

case $OSTYPE in
	"darwin"*)
		PLATFORM="darwin"
		;;

	"linux-gnu")
		PLATFORM="linux"
		;;
esac

print_usage() {
	read -r -d '' output << EOM

Highled - higher level ledger

Usage:
  highled init                 Configure highled (will be run once before any other command)
  highled flush                Remove all files created by highled
  highled pay <options>        Make a payment transaction (see detailed description below)
  highled last                 Print last transaction
  highled undo                 Remove last transaction
  highled withdraw <options>   Withdraw money from bank card (see below)
  highled set-alias <k> <v>    Set alias value <v> for the key <k>
  highled rm-alias <k>         Remove alias for the key <k>
  highled show-alias <k>       Print alias value for the key <k>, if <k> omitted print all
  highled exec <options>       Execute ledger with highled balance file and <options>
  highled print                Print dataset and config file locations
  highled {version|-v|-V}      Print highled version

Payment:
 highled pay [flags] [<date>] [-d <description>]
 Flags:
   -y             Auto-confirm transaction
   --no-alias     Don't try to resolve aliases
   -nas           Shorthand for --no-alias

Withdrawal:
 highled withdraw [flags] <amount> from <where> [<date>] [-d <description>]
 Flags: (the same as for payment)

EOM

	echo "$output" | less
}

init_config() {
	if [[ -f $CONFIG_FILE ]]; then
		return
	fi

	touch $CONFIG_FILE

	echo "# Default aliases" >> $CONFIG_FILE
	echo "DEFAULT_CURRENCY=EUR" >> $CONFIG_FILE
	echo "VISA=Liabilities:Visa" >> $CONFIG_FILE
	echo "MASTERCARD=Liabilities:MasterCard" >> $CONFIG_FILE
	echo "CASH=Assets:Cash" >> $CONFIG_FILE
}

init_dataset() {
	if [[ -f $DB_DATAFILE ]]; then
		return
	fi

	touch $DB_DATAFILE
	echo -e "; Currenty used dataset by highled" >> $DB_DATAFILE
	echo ";" >> $DB_DATAFILE
	echo "; Simple opening balance entry" >> $DB_DATAFILE
	echo "; See more http://www.ledger-cli.org/3.0/doc/ledger3.html#Starting-up" >> $DB_DATAFILE
	echo >> $DB_DATAFILE
	echo -e "; 2015/06/21  Opening Balance" >> $DB_DATAFILE
	echo -e ";   Assets:Checking     100 EUR" >> $DB_DATAFILE
	echo -e ";   Liabilities:Visa    600 EUR" >> $DB_DATAFILE
	echo -e ";   Equity:Opening Balances" >> $DB_DATAFILE


	echo "Hey $USER! Your opening balance should be configred first."
	echo
	echo "If you have ledger file already, type:"
	echo "  cp <path-to-your-dataset> $DB_DATAFILE"
	echo
	echo "Create opening balance entry"
	echo "  (see more: http://www.ledger-cli.org/3.0/doc/ledger3.html#Starting-up)"
	echo
	echo "Edit dataset with vim or with your favourite editor:"
	echo "  vim $DB_DATAFILE"
}

init_db() {
	if [[ ! -d $DB_DIR ]]; then
		mkdir $DB_DIR
	fi

	init_config
	init_dataset
}

flush_db() {
	if [[ -d $DB_DIR ]]; then
		rm -R $DB_DIR
	fi
}

rm_alias() {
	local key=`echo $1 | tr '[:lower:]' '[:upper:]'`
	if [[ $PLATFORM == "darwin" ]]; then
		sed -i '' -e /^$key=/d $CONFIG_FILE
	elif [[ $PLATFORM == "linux" ]]; then
		sed -i /^$key=/d $CONFIG_FILE
	else
		echo "Your platform is not supported yet."
	fi
}

get_alias() {
	if [ ! -r $CONFIG_FILE ]; then
		return 0
	fi

	local __resultvar=$2
	local key=`echo $1 | tr '[:lower:]' '[:upper:]'`
	local line=`grep -e "^$key=" $CONFIG_FILE | head -1`

	if [[ -z $line ]]; then
		return 0
	fi

	local val=${line##$key=}
	if [[ "$__resultvar" ]]; then
    eval $__resultvar="'$val'"
  else
    echo "$val"
  fi
}

set_alias() {
	local key=`echo $1 | tr '[:lower:]' '[:upper:]'`
	# local KEY=`echo $1 | awk '{ print toupper($0) }'`
	local value=$2

	if [ ! -f $CONFIG_FILE ]; then
		init_config
	fi

	if [ ! -w $CONFIG_FILE ]; then
		echo "Configuration file is not writable"
		exit 1
	fi

	rm_alias $key
	echo "$key=$value" >> $CONFIG_FILE
}

# Resolves string with amount and currency
# checks if input string has currency and if not
# appends default currency
resolve_amount_with_currency() {
  local __amount_with_currency=$1
	local __amount=${__amount_with_currency//[^0-9.,]/}
	local __currency=${__amount_with_currency//[0-9., ]/}

  get_alias "default_currency" __default_currency
  __currency=${__currency:=$__default_currency}

  local __val="$__amount $__currency"
	local __amount_currency=$2
	if [[ "$__amount_currency" ]]; then
    eval $__amount_currency="'$__val'"
  else
    echo "$__val"
  fi
}

# Resolves expense string using alias
# TODO: capitalize first letters
resolve_expense() {
  local __expense=$1
  get_alias $__expense __resolved

  if [[ -z $__resolved ]]; then
    __resolved=$__expense

    if [[ ! $__resolved =~ "Expenses:.*" ]]; then
      __resolved="Expenses:"$__resolved
    fi
  fi

  local __return_var=$2
  if [[ "$__return_var" ]]; then
    eval $__return_var="'$__resolved'"
  else
    echo "$__resolved"
  fi
}

# Resolves payment method by getting alias
resolve_payment_method() {
  local __method=$1
  get_alias $__method __resolved

  local __return_var=$2
  if [[ "$__return_var" ]]; then
    eval $__return_var="'$__resolved'"
  else
    echo "$__resolved"
  fi
}

pay() {
  # Usage:  highled pay [<flags>] [<date>] [-d <description>]

  local usage="Usage: highled pay [<flags>] [<date>] [-d <description>]"
  local autoconfirm
  local noalias
  local description
	local when=`date "+%Y/%m/%d"`

  # Parse command
  while [[ $# -gt 0 ]]; do
    local key=$1
    
    case $key in
      "-y")
        autoconfirm="true"
        ;;

      "-nas"|"--no-alias")
        noalias="true"
        ;;

      "-d")
        description="$2"
        shift
        ;;

      "yesterday")
				when=`date -v-1d "+%Y/%m/%d"`
				;;

			*)
				if [[ $key =~ ^[0-9]+(\/[0-9]+)+$ ]]; then
					when=$key
				else
					echo "Illegal date: $key"
					echo "Use form YYYY/MM/DD or \"yesterday\" instead"
					exit 1
				fi
				;;				

    esac
 
    shift
  done

	get_alias "$description" resolved_description
	description=${resolved_description:=$description}

  local expenselines=()
  local autodescription

  while [[ true ]]; do
    read -p "Debit: " debit
    if [[ -z $debit ]]; then
      break
    fi
    
    local expense=${debit%% *}
    local amount_with_currency=${debit#* }
    echo "amount_with_currency: $amount_with_currency"

    if [[ -z $amount_with_currency ]]; then
      echo "Specify payment amount."
      echo $usage
      exit 1
    fi	

    resolve_amount_with_currency "$amount_with_currency" resolved_amount
    resolve_expense "$expense" resolved_expense

    expenselines+=("$expense\t\t$resolved_amount")

    autodescription+="${expense##*:}, "
  done

  read -p "Credit: " credit
  if [[ -z $credit ]]; then
    echo "Specify at least one credit."
    echo $usage
    exit 1
  fi

  local method=$credit
  resolve_payment_method "$method" resolved_method

  autodescription="${autodescription%??} purchase with ${resolved_method##*:}"
  description=${description:=$autodescription}

	echo -e "$when  $description" > $TRANSACTION_FILE
  for line in "${expenselines[@]}"; do
    echo -e "  $line" >> $TRANSACTION_FILE
  done
	echo -e "  $resolved_method" >> $TRANSACTION_FILE

  cat $TRANSACTION_FILE

  # TODO: add option to modify transaction file
  if [[ $autoconfirm != "true" ]]; then
    read -p "Confirm (y/n):" yn
    case $yn in
      [Yy])
        ;;

      *)
        echo "Cancelling..."
        exit
    esac
  fi

  # TODO: check transaction file syntax
  cat $DB_DATAFILE > $DB_TMPFILE
  echo >> $DB_TMPFILE
  cat $TRANSACTION_FILE >> $DB_TMPFILE
  cat $DB_TMPFILE > $DB_DATAFILE
  rm $DB_TMPFILE
  rm $TRANSACTION_FILE
}

old_pay() {
  # Usage:   highled pay [<flags>] [<amount> for <expense>] with <what> [<date>] [-d <description>]
  # Example: highled pay -y 10 for Lunch with visa yesterday

	local usage="Usage: highled pay [<flags>] [<amount> for <expense>] with <what> [<date>] [-d <description>]"
	local autoconfirm
  local noalias

  # Parse flags
  while [[ $# -gt 0 ]]; do
    local flag=$1

    case $flag in
      "-y")
        autoconfirm="true"
        shift
        ;;

      "-nas"|"--no-alias")
        noalias="true"
        shift
        ;;
      
      *)
        break
        ;;
    esac
  done

  # Parse expenses
  local amounts=()
  local expenses=()
  while [[ $# -gt 0 ]]; do
    
    if [[ $1 == "with" ]]; then
      break
    fi

    if [[ $2 != "for" ]]; then
      echo "Missing \"for\""
      echo $usage
      exit 1
    fi
  
    local resolved_expense=""
    local resolved_amount=""

    resolve_amount_with_currency $1 resolved_amount

    if [[ -z $resolved_amount ]]; then
      echo "Specify payment amount."
      echo $usage
      exit 1
    fi	
    
    local expense=$3 
	  get_alias $expense resolved_expense
	  local expense=${resolved_expense:=$expense}

    amounts+=("$resolved_amount")
    expenses+=("$expense")

    shift
    shift
    shift
  done
  
  if [[ $1 != "with" ]]; then
    echo "Missing\"with\""
    echo $usage
    exit 1
  fi
  
  shift

  if [[ $# -eq 0 ]]; then
    echo "Specify payment method"
    echo $usage
    exit 1
  fi

	local pay_with=$1
  shift
	local when=`date "+%Y/%m/%d"`
	local description

	while [[ $# -gt 0 ]]; do
		local key=$1

		case $key in
			-d|--description)
				description=$2
				shift
				;;

			"yesterday"|"Yesterday")
				when=`date -v-1d "+%Y/%m/%d"`
				;;

			*)
				if [[ $key =~ ^[0-9]+(\/[0-9]+)+$ ]]; then
					when=$key
				else
					echo "$0 - illegal date: $key"
					echo "Use form YYYY/MM/DD or \"yesterday\" instead"
					exit 1
				fi
				;;				
		esac
		shift
	done

	get_alias $pay_with resolved_pay_with
	get_alias $description resolved_description

	pay_with=${resolved_pay_with:=$pay_with}
	description=${resolved_description:=$description}

  local total="${#amounts[*]}"
  local expenselines=()
  local autodescription

  for (( i=0; i<=$(( $total -1 )); i++ )); do
    local expense=${expenses[$i]}
    expenselines+=("Expenses:$expense\t\t${amounts[$i]}")
    autodescription+="${expense##*:}, "
  done

  autodescription="${autodescription%??} purchase with ${pay_with##*:}"
  description=${autodescription:=$description}

	echo -e "$when  $description"
  for line in "${expenselines[@]}"; do
    echo -e "  $line"
  done
	echo -e "  $pay_with"

  if [[ $autoconfirm != "true" ]]; then
    read -p "Confirm? (y/n):" yn
    case $yn in
      [Yy])
        ;;

      *)
        echo "Cancelling..."
        exit
    esac
  fi

	echo >> $DB_DATAFILE
	echo -e "$when  $description" >> $DB_DATAFILE
  for line in "${expenselines[@]}"; do
    echo -e "  $line" >> $DB_DATAFILE
  done
	echo -e "  $pay_with" >> $DB_DATAFILE
}

show_last() {
	if [[ $PLATFORM == "darwin" ]]; then
		tail -r $DB_DATAFILE | grep -E '^[0-9]+\/[0-9]+' -m 1 -B 20 | tail -r
	elif [[ $PLATFORM == "linux" ]]; then
		tac $DB_DATAFILE | grep -E '^[0-9]+\/[0-9]+' -m 1 -B 20 | tac
	else
		echo "Your platform is not supported yet."
		exit 1
	fi
}

undo_last() {
	local lines
	if [[ $PLATFORM == "darwin" ]]; then
		lines=`tail -r $DB_DATAFILE | grep -E '^[0-9]+\/[0-9]+' -m 1 -B 20 | tail -r | wc -l`
	elif [[ $PLATFORM == "linux" ]]; then
		lines=`tac $DB_DATAFILE | grep -E '^[0-9]+\/[0-9]+' -m 1 -B 20 | tac | wc -l`
	else
		echo "Your platform is not supported yet."
		exit 1
	fi

	local i="0"
	while [ $i -lt $lines ]; do
		if [[ $PLATFORM == "darwin" ]]; then
			sed -i '' -e '$ d' $DB_DATAFILE
		elif [[ $PLATFORM == "linux" ]]; then
			sed -i '$ d' $DB_DATAFILE
		fi
		i=$[$i+1]
	done
}

# Withdraw cash from the bank card
withdraw() {
  local usage="Usage: highled withdraw 10 from visa"

  if [[ $2 != "from" ]]; then
    echo "Missing \"from\""
    echo $usage
    exit 1
  fi

  local resolved_amount=""
  resolve_amount_with_currency $1 resolved_amount

  if [[ -z $resolved_amount ]]; then
    echo "Specify amount."
    echo $usage
    exit 1
  fi

  local from=$3
  local when=`date "+%Y/%m/%d"`

  get_alias $from resolved_from
  from=${resolved_from:=$from}

  echo -e "$when  ATM"
  echo -e "  Expenses:Cash\t\t$resolved_amount"
  echo -e "  $from"

  read -p "Confirm? (y/n):" yn
  case $yn in
    [Yy])
      ;;
    *)
      echo "Cancelling..."
      exit
      ;;
  esac

  echo >> $DB_DATAFILE
  echo -e "$when  ATM" >> $DB_DATAFILE
  echo -e "  Expenses:Cash\t\t$resolved_amount" >> $DB_DATAFILE
  echo -e "  $from" >> $DB_DATAFILE
}

# Main
case $1 in

	"init")
		init_db
		;;

	"flush")
		flush_db
		;;

	"pay")
		init_db
		shift
		pay "$@"
		;;

	"last")
		init_db
		shift
		show_last
		;;

	"undo")
		init_db
		shift
		undo_last
		;;

  "withdraw")
    init_db
    shift
    withdraw "$@"
    ;;
    
	"set-alias")
		init_db
		shift
		set_alias "$@"
		;;

	"rm-alias")
		init_db
		shift
		rm_alias "$@"
		;;

	"show-alias")
		init_db
		if [[ -z $2 ]]; then
			cat $CONFIG_FILE | less
		else
			get_alias $2
		fi
		;;

	"exec")
		init_db
		shift
		ledger -f $DB_DATAFILE "$@"
		;;

	"print")
		echo -e "Dataset:\t$DB_DATAFILE"
		echo -e "Configuration:\t$CONFIG_FILE"
		;;

  "version"|"-v"|"-V")
    echo "highled v$VERSION"
    ;;

	*)
		print_usage
		exit
esac

}
